import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { QuickApps } from "./QuickApps";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ActionStatusProvider } from "../state/ActionStatusProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import type { DashboardState } from "../state/dashboardState";

/** NIC-119 part 1 (NIC-85): quick app tiles reflect capability flags and dispatch
 *  `open <id>` through the bridge — honest-disabled when the capability is absent. */

function renderQuickApps(
  mutate?: (base: DashboardState) => DashboardState,
  spies?: { onUpdateQuickApps?: (input: { modeId: string; quickApps: readonly string[] }) => void }
) {
  const bridge = createMockCerebralBridge();
  const submissions: string[] = [];
  const spyBridge = {
    ...bridge,
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return bridge.submitCommand(input);
    },
    updateQuickApps(input: { modeId: string; quickApps: readonly string[] }) {
      spies?.onUpdateQuickApps?.(input);
      return bridge.updateQuickApps(input);
    }
  };
  const base = loadBootstrapState();
  const store = createBridgeStore(spyBridge, mutate ? mutate(base) : base);
  render(
    <BridgeProvider bridge={spyBridge}>
      <DashboardStateProvider store={store}>
        <ActionStatusProvider>
          <QuickApps />
        </ActionStatusProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { submissions };
}

/** Pin one app into the active (Executive) mode — modes ship clean-slate now. */
function withPinnedApp(base: DashboardState): DashboardState {
  return {
    ...base,
    modes: base.modes.map((mode) =>
      mode.id === "executive" ? { ...mode, quickApps: ["vscode"] } : mode
    )
  };
}

function firstAppTile(): HTMLButtonElement {
  const list = screen.getByRole("list");
  const tile = list.querySelector<HTMLButtonElement>("button.quick-app");
  if (!tile) {
    throw new Error("expected at least one quick-app tile");
  }
  return tile;
}

describe("QuickApps", () => {
  it("stays honest-disabled while native.app.open is not reported available", () => {
    renderQuickApps(withPinnedApp);
    const tile = firstAppTile();
    expect(tile).toBeDisabled();
    expect(tile.title).toMatch(/macOS host/);
  });

  it("reports the capability's own degraded reason when one is given", () => {
    renderQuickApps((base) => ({
      ...withPinnedApp(base),
      capabilities: {
        "native.app.open": { available: false, degradedReason: "Permission denied by the user." }
      }
    }));
    expect(firstAppTile().title).toBe("Permission denied by the user.");
  });

  it("ships a clean slate: no placeholder tiles, five Pin app slots (release MVP)", () => {
    renderQuickApps();
    expect(screen.getAllByRole("button", { name: "Pin app" })).toHaveLength(5);
    expect(
      document.querySelectorAll("button.quick-app:not(.quick-app--pin):not(.quick-app--more)")
    ).toHaveLength(0);
  });

  it("dispatches `open <id>` through the bridge when the capability is available", () => {
    const { submissions } = renderQuickApps((base) => ({
      ...withPinnedApp(base),
      capabilities: { "native.app.open": { available: true } }
    }));
    const tile = firstAppTile();
    expect(tile).toBeEnabled();

    fireEvent.click(tile);
    expect(submissions).toHaveLength(1);
    expect(submissions[0]).toMatch(/^open [a-z][a-z0-9-]*$/);
  });

  it("keeps every tile disabled in read-only recovery, capability or not (NIC-64)", () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.app.open": { available: true } },
      recovery: { reason: "Recovering.", startupMode: "recovery" }
    }));
    expect(firstAppTile()).toBeDisabled();
  });

  it("pin controls remain honest-disabled and More Apps gates on native.apps.list (NIC-119)", () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.app.open": { available: true } }
    }));
    const more = screen.getByRole("button", { name: /More Apps/ });
    expect(more).toBeDisabled();
    expect(more.title).toMatch(/macOS host/);
  });

  it("More Apps opens the read-only discovery picker when the capability is available", async () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.apps.list": { available: true } }
    }));
    const more = screen.getByRole("button", { name: /More Apps/ });
    expect(more).toBeEnabled();

    fireEvent.click(more);
    const dialog = await screen.findByRole("dialog", { name: "All applications" });
    // The mock discovery catalog renders by app name — real icons come from the Mac adapter.
    expect(await screen.findByText("Safari")).toBeInTheDocument();
    expect(screen.getByText("Visual Studio Code")).toBeInTheDocument();

    fireEvent.keyDown(dialog, { key: "Escape" });
    expect(screen.queryByRole("dialog", { name: "All applications" })).toBeNull();
  });

  it("picker tiles launch via `open <referenceId>` and close the picker (NIC-149)", async () => {
    const { submissions } = renderQuickApps((base) => ({
      ...base,
      capabilities: {
        "native.apps.list": { available: true },
        "native.app.open": { available: true }
      }
    }));

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });
    await screen.findByText("Terminal");

    // Terminal is reference-backed: its tile is a live launch button.
    const tile = screen.getByRole("button", { name: "Terminal" });
    expect(tile).toBeEnabled();
    fireEvent.click(tile);
    expect(submissions).toEqual(["open terminal"]);

    // An accepted launch closes the picker (launcher semantics).
    await waitFor(() =>
      expect(screen.queryByRole("dialog", { name: "All applications" })).toBeNull()
    );
  });

  it("picker launch controls stay honest-disabled without native.app.open (NIC-149)", async () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.apps.list": { available: true } }
    }));

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });
    await screen.findByText("Terminal");

    // Reference-backed but no launch capability: disabled with the honest reason.
    const tile = screen.getByRole("button", { name: "Terminal" });
    expect(tile).toBeDisabled();
    expect(tile.title).toMatch(/macOS host/);
    // No configured reference: disabled regardless, and says why.
    const safari = screen.getByRole("button", { name: "Safari" });
    expect(safari).toBeDisabled();
    expect(safari.title).toBe("Not a configured app reference");
  });

  it("an accepted pin re-renders the tiles from mode.quickapps.changed (NIC-149)", async () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.apps.list": { available: true } }
    }));

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });
    await screen.findByText("Terminal");

    // Clean slate: five empty Pin app slots before the write.
    expect(screen.getAllByRole("button", { name: "Pin app" })).toHaveLength(5);

    fireEvent.click(screen.getAllByRole("button", { name: "Pin" })[0]);

    // The mock bridge emits mode.quickapps.changed on the accepted write — a
    // pinned tile appears and its picker control flips to Unpin, no restart.
    await waitFor(() => expect(screen.getAllByRole("button", { name: "Pin app" })).toHaveLength(4));
    expect(await screen.findByRole("button", { name: "Unpin" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Unpin Terminal" })).toBeInTheDocument();
  });

  it("pins a reference-backed app through updateQuickApps; unbacked apps say so (NIC-119c)", async () => {
    const updates: Array<{ modeId: string; quickApps: readonly string[] }> = [];
    renderQuickApps(
      (base) => ({
        ...base,
        capabilities: { "native.apps.list": { available: true } }
      }),
      {
        onUpdateQuickApps: (input) => updates.push(input)
      }
    );

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });

    // Safari has no configured reference — honest hint, no pin control.
    expect(await screen.findAllByText("Not a configured app reference")).not.toHaveLength(0);

    // Terminal is reference-backed: pinning submits mode id + the extended slot set.
    const pins = screen.getAllByRole("button", { name: "Pin" });
    fireEvent.click(pins[0]);
    expect(updates).toHaveLength(1);
    expect(updates[0].modeId).toMatch(/^[a-z][a-z0-9-]*$/);
    expect(updates[0].quickApps).toContain("terminal");
  });

  it("adds a URL from the picker; it pins as a globe tile that opens by id (NIC-146)", async () => {
    const { submissions } = renderQuickApps((base) => ({
      ...base,
      capabilities: {
        "native.apps.list": { available: true },
        "native.app.open": { available: true }
      }
    }));

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });

    fireEvent.change(screen.getByLabelText("URL"), {
      target: { value: "https://news.ycombinator.com" }
    });
    fireEvent.change(screen.getByLabelText("URL name (optional)"), {
      target: { value: "Hacker News" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    // The URL pins into the active mode and renders as a launchable tile carrying
    // its real label (resolved from listUrls, not its slug id).
    const tile = await screen.findByRole("button", { name: "Hacker News" });
    await waitFor(() => expect(screen.getAllByRole("button", { name: "Pin app" })).toHaveLength(4));

    // The tile launches through the same deterministic `open <id>` path as an app.
    fireEvent.click(tile);
    expect(submissions).toContain("open hacker-news");
  });

  it("rejects a non-web URL in the picker, pinning nothing (NIC-146)", async () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.apps.list": { available: true } }
    }));

    fireEvent.click(screen.getByRole("button", { name: /More Apps/ }));
    await screen.findByRole("dialog", { name: "All applications" });

    fireEvent.change(screen.getByLabelText("URL"), { target: { value: "file:///etc/passwd" } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    expect(await screen.findByText(/Only http and https/)).toBeInTheDocument();
    // Nothing was pinned — all five slots remain empty.
    expect(screen.getAllByRole("button", { name: "Pin app" })).toHaveLength(5);
  });

  it("empty Pin app slots open the picker when discovery is available", async () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.apps.list": { available: true } }
    }));
    const pinSlot = screen.getAllByRole("button", { name: "Pin app" })[0];
    expect(pinSlot).toBeEnabled();
    fireEvent.click(pinSlot);
    expect(await screen.findByRole("dialog", { name: "All applications" })).toBeInTheDocument();
  });
});
