import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { confirmationBridgeEvent, lifecycleBridgeEvents } from "../bridge/eventFixtures";
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
    expect(reduceDashboardState(base, lifecycleEvent("requires_confirmation")).heimlich.state).toBe(
      "awaiting_confirmation"
    );
    expect(reduceDashboardState(base, lifecycleEvent("failed")).heimlich.state).toBe("error");
  });

  it("returns the same reference when nothing changes (no needless re-render)", () => {
    const base = loadBootstrapState();
    expect(reduceDashboardState(base, IRRELEVANT_EVENT)).toBe(base);
    // An unknown lifecycle status also leaves state untouched.
    expect(reduceDashboardState(base, lifecycleEvent("idle"))).toBe(base);
  });

  it("folds workflow action progress in and clears it on the terminal lifecycle status (NIC-85)", () => {
    const base = loadBootstrapState();
    const progress: BridgeEvent = {
      eventId: "brevt_wfprogress01",
      type: "workflow.action.progress",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        commandId: "cmd_000000000000000000000001",
        workflowId: "open-developer-layout",
        actionId: "open-editor",
        kind: "app.open",
        status: "running",
        index: 2,
        total: 5
      }
    };

    const running = reduceDashboardState(base, progress);
    expect(running.activeWorkflowRun?.workflowId).toBe("open-developer-layout");
    expect(running.activeWorkflowRun?.status).toBe("running");
    expect(running.activeWorkflowRun?.index).toBe(2);
    expect(running.activeWorkflowRun?.total).toBe(5);

    // The command's terminal lifecycle status ends the live run.
    const done = reduceDashboardState(running, lifecycleEvent("succeeded"));
    expect(done.activeWorkflowRun ?? null).toBeNull();

    // A malformed payload never fabricates a run.
    const malformed = reduceDashboardState(base, { ...progress, payload: { status: "running" } });
    expect(malformed).toBe(base);
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

  it("folds every capability change into the availability map (FR-SHL-06)", () => {
    const base = loadBootstrapState();
    const capabilityEvent = (id: string, available: boolean): BridgeEvent => ({
      eventId: `brevt_cap_${id}`,
      type: "bridge.capability.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { capability: { id, available, degradedReason: available ? null : "Denied." } }
    });

    const granted = reduceDashboardState(base, capabilityEvent("native.app.open", true));
    expect(granted.capabilities?.["native.app.open"]?.available).toBe(true);

    // A later revocation flips the same entry and keeps others.
    const revoked = reduceDashboardState(granted, capabilityEvent("native.app.open", false));
    expect(revoked.capabilities?.["native.app.open"]?.available).toBe(false);
    expect(revoked.capabilities?.["native.app.open"]?.degradedReason).toBe("Denied.");

    // A malformed payload never fabricates an entry.
    expect(
      reduceDashboardState(base, {
        ...capabilityEvent("x", true),
        payload: { capability: { id: "x" } }
      })
    ).toBe(base);
  });

  it("folds a confirmation disclosure in on confirmation.changed and back out on null", () => {
    const base = loadBootstrapState();
    expect(base.activeConfirmation ?? null).toBeNull();

    const withConfirmation = reduceDashboardState(base, confirmationBridgeEvent);
    expect(withConfirmation.activeConfirmation?.id).toBe("conf_000000000000000000000001");

    const cleared = reduceDashboardState(withConfirmation, {
      eventId: "brevt_confcleared99",
      type: "confirmation.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:45.000Z",
      payload: { confirmation: null }
    });
    expect(cleared.activeConfirmation ?? null).toBeNull();
    // Clearing an already-absent confirmation is a no-op (same reference, no re-render).
    expect(
      reduceDashboardState(cleared, { ...confirmationBridgeEvent, payload: { confirmation: null } })
    ).toBe(cleared);
  });

  it("folds a live system_metrics snapshot into the system-health region (NIC-81b)", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics01",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        cpu: { availability: "available", value: 23.5, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        memory: { availability: "available", value: 61.2, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        network: {
          availability: "available",
          uploadMbps: 2.1,
          downloadMbps: 8.4,
          unit: "mbps",
          sampledAt: "2026-06-23T16:00:00.000Z"
        },
        battery: {
          availability: "available",
          value: 76,
          charging: true,
          pluggedIn: true,
          unit: "percent",
          sampledAt: "2026-06-23T16:00:00.000Z"
        },
        display: { availability: "available", value: 2, unit: null, sampledAt: "2026-06-23T16:00:00.000Z" }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.state).toBe("ready");
    expect(health.cpuPercent).toBe(23.5);
    expect(health.memoryPercent).toBe(61.2);
    expect(health.network?.uploadMbps).toBe(2.1);
    expect(health.network?.downloadMbps).toBe(8.4);
    expect(health.battery.percent).toBe(76);
    expect(health.battery.state).toBe("ready");
    expect(health.battery.charging).toBe(true);
    expect(health.battery.pluggedIn).toBe(true);
  });

  it("maps per-channel degradation honestly: no battery is unavailable, warming rates are empty", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics02",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        // First tick on a desktop Mac: rate metrics still warming, no battery.
        cpu: { availability: "loading", value: null, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        memory: { availability: "available", value: 40, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        network: { availability: "loading", uploadMbps: null, downloadMbps: null, unit: "mbps", sampledAt: null },
        battery: { availability: "unavailable", value: null, unit: "percent", sampledAt: null },
        display: { availability: "available", value: 1, unit: null, sampledAt: "2026-06-23T16:00:00.000Z" }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.state).toBe("ready");
    expect(health.cpuPercent).toBeUndefined();
    expect(health.memoryPercent).toBe(40);
    expect(health.network?.state).toBe("empty");
    expect(health.battery.state).toBe("unavailable");
    expect(health.battery.percent).toBeUndefined();
  });

  it("still folds bridge_failure status changes into read-only recovery (NIC-64)", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_failure01",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "bridge_failure",
        state: { status: "read_only", message: "Bridge is in read-only recovery." }
      }
    };
    expect(reduceDashboardState(base, event).recovery?.startupMode).toBe("recovery");
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
