import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MoreAppsPicker } from "./MoreAppsPicker";
import { BridgeProvider } from "../state/BridgeProvider";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState, DashboardStore } from "../state/dashboardState";
import type { BridgeEventListener, CerebralBridge, DiscoveredApp } from "../bridge/cerebralBridge";

afterEach(cleanup);

const APPS: readonly DiscoveredApp[] = [
  { bundleId: "com.apple.Safari", name: "Safari", referenceId: "safari" },
  { bundleId: "com.apple.Terminal", name: "Terminal", referenceId: "terminal" },
  { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", referenceId: "vscode" }
];

function stubBridge(
  apps: readonly DiscoveredApp[] = APPS,
  submitted: string[] = []
): CerebralBridge {
  return {
    listApps: () => Promise.resolve({ apps, truncated: false }),
    submitCommand: (input: { rawInput: string }) => {
      submitted.push(input.rawInput);
      return Promise.resolve({ accepted: true, commandId: "cmd_1" });
    },
    subscribe: (_listener: BridgeEventListener) => () => {}
  } as unknown as CerebralBridge;
}

/** Capabilities matter here: launching is gated on `native.app.open`. */
function staticStore(): DashboardStore {
  const state: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready"),
    capabilities: { "native.app.open": { id: "native.app.open", available: true } }
  } as DashboardState;
  return { getState: () => state, subscribe: () => () => {} };
}

function renderPicker(overrides: { bridge?: CerebralBridge; onClose?: () => void } = {}) {
  const onClose = overrides.onClose ?? vi.fn();
  const view = render(
    <BridgeProvider bridge={overrides.bridge ?? stubBridge()}>
      <DashboardStateProvider store={staticStore()}>
        <MoreAppsPicker onClose={onClose} />
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { ...view, onClose };
}

const tiles = () =>
  [...document.querySelectorAll(".apps-picker__name")].map((el) => el.textContent ?? "");

describe("MoreAppsPicker search (NIC-167)", () => {
  it("filters the launcher grid live as the user types", async () => {
    renderPicker();
    await waitFor(() => expect(tiles()).toHaveLength(3));

    const search = screen.getByLabelText("Search applications");
    fireEvent.change(search, { target: { value: "vis" } });
    expect(tiles()).toEqual(["Visual Studio Code"]);

    fireEvent.change(search, { target: { value: "" } });
    expect(tiles()).toEqual(["Safari", "Terminal", "Visual Studio Code"]);
  });

  it("takes mount focus so the launcher is ready to be typed into", async () => {
    renderPicker();
    await waitFor(() => expect(screen.getByLabelText("Search applications")).toHaveFocus());
  });

  it("still closes on Escape while the search field holds focus", async () => {
    const onClose = vi.fn();
    renderPicker({ onClose });
    const search = await screen.findByLabelText("Search applications");

    // The field owns focus now, so Escape must bubble to the dialog handler.
    fireEvent.keyDown(search, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("launches the app the user filtered down to", async () => {
    const submitted: string[] = [];
    renderPicker({ bridge: stubBridge(APPS, submitted) });
    await waitFor(() => expect(tiles()).toHaveLength(3));

    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "term" } });
    // The tile's accessible name is its content (the app name); `title` carries the hint only.
    fireEvent.click(screen.getByRole("button", { name: "Terminal" }));

    await waitFor(() => expect(submitted).toEqual(["open terminal"]));
  });

  it("separates an empty search from an empty inventory", async () => {
    renderPicker();
    await waitFor(() => expect(tiles()).toHaveLength(3));
    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "zzz" } });
    expect(screen.getByText(/No applications match/)).toBeInTheDocument();

    cleanup();
    renderPicker({ bridge: stubBridge([]) });
    await waitFor(() => expect(screen.getByText("No applications found.")).toBeInTheDocument());
    expect(screen.queryByText(/No applications match/)).toBeNull();
  });
});
