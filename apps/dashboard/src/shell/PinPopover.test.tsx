import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PinPopover } from "./PinPopover";
import { BridgeProvider } from "../state/BridgeProvider";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { DashboardState, DashboardStore } from "../state/dashboardState";
import type {
  BridgeEventListener,
  CerebralBridge,
  ChromeProfile,
  DiscoveredApp
} from "../bridge/cerebralBridge";

afterEach(cleanup);

const APPS: readonly DiscoveredApp[] = [
  { bundleId: "com.apple.Safari", name: "Safari", referenceId: "safari" },
  { bundleId: "com.apple.Terminal", name: "Terminal", referenceId: "terminal" },
  { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", referenceId: "vscode" }
];

const PROFILES: readonly ChromeProfile[] = [
  { directory: "Default", name: "Personal" },
  { directory: "Profile 1", name: "Work" }
];

function stubBridge(apps: readonly DiscoveredApp[] = APPS): CerebralBridge {
  return {
    listApps: () => Promise.resolve({ apps, truncated: false }),
    listChromeProfiles: () => Promise.resolve({ profiles: PROFILES, references: [] }),
    updateQuickApps: () => Promise.resolve({ applied: true, quickApps: [] }),
    subscribe: (_listener: BridgeEventListener) => () => {}
  } as unknown as CerebralBridge;
}

function staticStore(): DashboardStore {
  const state: DashboardState = {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.executive.ready")
  };
  return { getState: () => state, subscribe: () => () => {} };
}

function renderPopover(overrides: { bridge?: CerebralBridge; onClose?: () => void } = {}) {
  const onClose = overrides.onClose ?? vi.fn();
  // The popover positions itself against a real element (the empty quick-app slot that was
  // clicked), so the harness supplies one rather than a rect.
  const anchor = document.createElement("button");
  document.body.appendChild(anchor);
  const view = render(
    <BridgeProvider bridge={overrides.bridge ?? stubBridge()}>
      <DashboardStateProvider store={staticStore()}>
        <PinPopover anchor={anchor} onClose={onClose} />
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { ...view, onClose };
}

/** Row names within a named section, so the two lists can be asserted independently. */
function rowsIn(sectionLabel: string): string[] {
  const section = screen.getByRole("region", { name: sectionLabel });
  return [...section.querySelectorAll(".pin-pop__name")].map((el) => el.textContent ?? "");
}

describe("PinPopover search (NIC-167)", () => {
  it("filters the application list live as the user types", async () => {
    renderPopover();
    await waitFor(() => expect(rowsIn("Applications")).toHaveLength(3));

    const search = screen.getByLabelText("Search applications");
    fireEvent.change(search, { target: { value: "saf" } });
    expect(rowsIn("Applications")).toEqual(["Safari"]);

    fireEvent.change(search, { target: { value: "" } });
    expect(rowsIn("Applications")).toEqual(["Safari", "Terminal", "Visual Studio Code"]);
  });

  it("leaves the Chrome-profile list alone (owner decision, NIC-167)", async () => {
    renderPopover();
    await waitFor(() => expect(rowsIn("Chrome profiles")).toHaveLength(2));

    // The profile list is short and fixed; hiding it on an app query would surprise. A query that
    // matches no profile must not empty that section.
    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "saf" } });
    expect(rowsIn("Applications")).toEqual(["Safari"]);
    expect(rowsIn("Chrome profiles")).toEqual(["Chrome — Personal", "Chrome — Work"]);
  });

  it("takes mount focus and still closes on Escape", async () => {
    const onClose = vi.fn();
    renderPopover({ onClose });
    const search = await screen.findByLabelText("Search applications");
    await waitFor(() => expect(search).toHaveFocus());

    fireEvent.keyDown(search, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it("separates an empty search from an empty inventory", async () => {
    renderPopover();
    await waitFor(() => expect(rowsIn("Applications")).toHaveLength(3));
    fireEvent.change(screen.getByLabelText("Search applications"), { target: { value: "zzz" } });
    expect(screen.getByText(/No applications match/)).toBeInTheDocument();

    cleanup();
    renderPopover({ bridge: stubBridge([]) });
    await waitFor(() => expect(screen.getByText("No applications found.")).toBeInTheDocument());
    expect(screen.queryByText(/No applications match/)).toBeNull();
  });
});
