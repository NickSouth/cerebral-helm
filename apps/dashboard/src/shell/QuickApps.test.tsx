import { render, screen, fireEvent } from "@testing-library/react";
import { QuickApps } from "./QuickApps";
import { DashboardStateProvider } from "../state/DashboardStateProvider";
import { BridgeProvider } from "../state/BridgeProvider";
import { ConversationProvider } from "../state/ConversationProvider";
import { createBridgeStore } from "../state/bridgeStore";
import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import type { DashboardState } from "../state/dashboardState";

/** NIC-119 part 1 (NIC-85): quick app tiles reflect capability flags and dispatch
 *  `open <id>` through the bridge — honest-disabled when the capability is absent. */

function renderQuickApps(mutate?: (base: DashboardState) => DashboardState) {
  const bridge = createMockCerebralBridge();
  const submissions: string[] = [];
  const spyBridge = {
    ...bridge,
    submitCommand(input: { rawInput: string; source: string }) {
      submissions.push(input.rawInput);
      return bridge.submitCommand(input);
    }
  };
  const base = loadBootstrapState();
  const store = createBridgeStore(spyBridge, mutate ? mutate(base) : base);
  render(
    <BridgeProvider bridge={spyBridge}>
      <DashboardStateProvider store={store}>
        <ConversationProvider>
          <QuickApps />
        </ConversationProvider>
      </DashboardStateProvider>
    </BridgeProvider>
  );
  return { submissions };
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
    renderQuickApps();
    const tile = firstAppTile();
    expect(tile).toBeDisabled();
    expect(tile.title).toMatch(/macOS host/);
  });

  it("reports the capability's own degraded reason when one is given", () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: {
        "native.app.open": { available: false, degradedReason: "Permission denied by the user." }
      }
    }));
    expect(firstAppTile().title).toBe("Permission denied by the user.");
  });

  it("dispatches `open <id>` through the bridge when the capability is available", () => {
    const { submissions } = renderQuickApps((base) => ({
      ...base,
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

  it("pin and More Apps controls remain honest-disabled (discovery/pinning land later)", () => {
    renderQuickApps((base) => ({
      ...base,
      capabilities: { "native.app.open": { available: true } }
    }));
    const more = screen.getByRole("button", { name: /More Apps/ });
    expect(more).toBeDisabled();
  });
});
