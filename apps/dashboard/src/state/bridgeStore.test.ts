import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { lifecycleBridgeEvents } from "../bridge/eventFixtures";
import { getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { BridgeEvent } from "../bridge/cerebralBridge";
import { createBridgeStore, reduceDashboardState } from "./bridgeStore";

const IRRELEVANT_EVENT: BridgeEvent = {
  eventId: "brevt_irrelevant1",
  type: "config.changed",
  schemaVersion: "1.0.0",
  timestamp: "2026-06-23T16:00:00.000Z",
  payload: {}
};

function lifecycleEvent(currentStatus: string): BridgeEvent {
  return {
    eventId: `brevt_${currentStatus}`,
    type: "command.lifecycle.transition",
    schemaVersion: "1.0.0",
    timestamp: "2026-06-23T16:00:00.000Z",
    payload: { currentStatus }
  };
}

describe("reduceDashboardState", () => {
  it("maps command-lifecycle status onto Heimlich state", () => {
    const base = loadBootstrapState();
    expect(reduceDashboardState(base, lifecycleEvent("running")).heimlich.state).toBe("acting");
    expect(reduceDashboardState(base, lifecycleEvent("requires_confirmation")).heimlich.state).toBe("awaiting_confirmation");
    expect(reduceDashboardState(base, lifecycleEvent("failed")).heimlich.state).toBe("error");
  });

  it("returns the same reference when nothing changes (no needless re-render)", () => {
    const base = loadBootstrapState();
    expect(reduceDashboardState(base, IRRELEVANT_EVENT)).toBe(base);
    // An unknown lifecycle status also leaves state untouched.
    expect(reduceDashboardState(base, lifecycleEvent("idle"))).toBe(base);
  });

  it("degrades system health when metrics become unavailable", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_cap0001",
      type: "bridge.capability.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { capability: { id: "system.metrics", available: false } }
    };
    expect(reduceDashboardState(base, event).regions.systemHealth.state).toBe("stale");
  });

  it("applies a mode-switch snapshot on config.changed, preserving the eager bundle", () => {
    const base = loadBootstrapState(); // Executive default
    const snapshot = getDashboardFixture("mode.school.ready");
    const event: BridgeEvent = {
      eventId: "brevt_config1",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { snapshot }
    };

    const next = reduceDashboardState(base, event);

    expect(next.mode).toBe("School");
    // The preloaded modes/agents bundle is preserved by reference; only the per-state slice swaps.
    expect(next.modes).toBe(base.modes);
    expect(next.agents).toBe(base.agents);
  });
});

describe("createBridgeStore", () => {
  it("seeds from initial state and folds the bridge event stream", () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());

    expect(store.getState().heimlich.state).toBe("idle");

    let notifications = 0;
    const unsubscribe = store.subscribe(() => {
      notifications += 1;
    });

    const runningEvent = lifecycleBridgeEvents.find(
      (event) => (event.payload as { currentStatus: string }).currentStatus === "running"
    )!;
    bridge.emit(runningEvent);

    expect(store.getState().heimlich.state).toBe("acting");
    expect(notifications).toBe(1);

    unsubscribe();
    bridge.emit(runningEvent);
    expect(notifications).toBe(1);
  });

  it("does not notify subscribers on an irrelevant event", () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());

    let notifications = 0;
    store.subscribe(() => {
      notifications += 1;
    });

    bridge.emit(IRRELEVANT_EVENT);
    expect(notifications).toBe(0);
  });
});
