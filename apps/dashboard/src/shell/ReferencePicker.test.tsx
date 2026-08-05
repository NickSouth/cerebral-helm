import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ReferencePicker } from "./ReferencePicker";
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

function stubBridge(apps: readonly DiscoveredApp[] = APPS): CerebralBridge {
  return {
    listApps: () => Promise.resolve({ apps, truncated: false }),
    listChromeProfiles: () => Promise.resolve({ profiles: [], references: [] }),
    subscribe: (_listener: BridgeEventListener) => () => {}
  } as unknown as CerebralBridge;
}

/** A static store over a fixed state — the picker only reads posture from it. */
function staticStore(): DashboardStore {
  const state: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  return { getState: () => state, subscribe: () => () => {} };
}

function renderPicker(overrides: { onClose?: () => void; bridge?: CerebralBridge } = {}) {
  const onPick = vi.fn();
  const onClose = overrides.onClose ?? vi.fn();
  const view = render(
    <BridgeProvider bridge={overrides.bridge ?? stubBridge()}>
      <DashboardStateProvider store={staticStore()}>
        <ReferencePicker
          onPick={onPick}
          onClose={onClose}
          title="Add a hotswap window"
          ariaLabel="Add a layout window"
        />
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { ...view, onPick, onClose };
}

/** The application rows currently rendered, by visible name. */
function listedApps(): string[] {
  const section = screen.getByRole("region", { name: "Applications" });
  return [...section.querySelectorAll(".pin-pop__name")].map((el) => el.textContent ?? "");
}

describe("ReferencePicker search (NIC-167)", () => {
  it("filters the application list live as the user types", async () => {
    renderPicker();
    await waitFor(() => expect(listedApps()).toHaveLength(3));

    const search = screen.getByLabelText("Search applications");
    fireEvent.change(search, { target: { value: "term" } });
    expect(listedApps()).toEqual(["Terminal"]);

    // Clearing restores the full list rather than leaving it narrowed.
    fireEvent.change(search, { target: { value: "" } });
    expect(listedApps()).toEqual(["Safari", "Terminal", "Visual Studio Code"]);
  });

  it("takes mount focus, so the surface is ready to be typed into", async () => {
    renderPicker();
    await waitFor(() => expect(screen.getByLabelText("Search applications")).toHaveFocus());
  });

  it("still closes on Escape while the search field holds focus", async () => {
    const onClose = vi.fn();
    renderPicker({ onClose });
    const search = await screen.findByLabelText("Search applications");
    fireEvent.change(search, { target: { value: "saf" } });

    // Regression guard: the field now owns focus, so Escape must bubble to the dialog. Swallowing
    // it in the input would break the established "Escape closes the picker" behaviour.
    fireEvent.keyDown(search, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("reports an empty search honestly, and distinguishes it from an empty inventory", async () => {
    renderPicker();
    await waitFor(() => expect(listedApps()).toHaveLength(3));

    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "zzz" } });
    expect(listedApps()).toEqual([]);
    expect(screen.getByText(/No applications match/)).toBeInTheDocument();
  });

  it("says the inventory is empty — not that the search failed — when no apps exist", async () => {
    renderPicker({ bridge: stubBridge([]) });
    await waitFor(() => expect(screen.getByText("No applications found.")).toBeInTheDocument());
    expect(screen.queryByText(/No applications match/)).toBeNull();
  });

  it("still adds the app the user picked after filtering", async () => {
    const { onPick } = renderPicker();
    await waitFor(() => expect(listedApps()).toHaveLength(3));

    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "vs" } });
    const section = screen.getByRole("region", { name: "Applications" });
    fireEvent.click(within(section).getByRole("button", { name: "Add Visual Studio Code" }));

    expect(onPick).toHaveBeenCalledWith("vscode", "app", "Visual Studio Code");
  });
});
