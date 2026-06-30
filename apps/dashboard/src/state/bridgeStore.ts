import type { BridgeEvent, CerebralBridge } from "../bridge/cerebralBridge";
import type { DashboardStateSnapshot, HeimlichState } from "../bridge/types";
import type { DashboardState, DashboardStore } from "./dashboardState";

/** How a command-lifecycle status maps onto Heimlich's consciousness state (design spec §5.8). */
const LIFECYCLE_TO_HEIMLICH: Readonly<Record<string, HeimlichState>> = {
  received: "thinking",
  planned: "thinking",
  requires_confirmation: "awaiting_confirmation",
  running: "acting",
  succeeded: "success",
  failed: "error",
  cancelled: "idle"
};

/**
 * Pure reducer: fold one bridge event into dashboard state. Returns the SAME reference when
 * nothing changes, so useSyncExternalStore does not trigger a needless re-render. Event
 * types whose UI lands later are observed but not yet interpreted: `confirmation.changed`
 * (NIC-62), `system.status.changed` (NIC-64 degraded states).
 */
export function reduceDashboardState(state: DashboardState, event: BridgeEvent): DashboardState {
  switch (event.type) {
    case "config.changed": {
      // A mode switch (NIC-54/D2): apply the target mode's per-state snapshot over the eager
      // bundle. Keeps the preloaded `modes`/`agents`; swaps mode/regions/heimlich/expandedAgent
      // and re-themes via data-mode without remounting the shell.
      const snapshot = (event.payload as { snapshot?: DashboardStateSnapshot }).snapshot;
      if (!snapshot || snapshot.mode === state.mode) {
        return state;
      }
      return { ...state, ...snapshot };
    }
    case "command.lifecycle.transition": {
      const status = String((event.payload as { currentStatus?: unknown }).currentStatus ?? "");
      const next = LIFECYCLE_TO_HEIMLICH[status];
      if (!next || next === state.heimlich.state) {
        return state;
      }
      return { ...state, heimlich: { ...state.heimlich, state: next } };
    }
    case "bridge.capability.changed": {
      const capability = (event.payload as { capability?: { id?: string; available?: boolean } }).capability;
      const metricsDown = capability?.id === "system.metrics" && capability.available === false;
      if (!metricsDown || state.regions.systemHealth.state === "stale") {
        return state;
      }
      return {
        ...state,
        regions: {
          ...state.regions,
          systemHealth: { ...state.regions.systemHealth, state: "stale" }
        }
      };
    }
    default:
      return state;
  }
}

/**
 * An event-driven DashboardStore backed by a CerebralBridge. Seeded synchronously from
 * `initialState` (so consumers render immediately with no loading flash), then updated by
 * reducing the bridge's event stream. The seam (getState + subscribe) is unchanged for
 * consumers; useDashboardState does not change. The native WKWebView transport swaps the
 * bridge — and would additionally `await bridge.getBootstrapState()` for its seed — without
 * touching components.
 */
export function createBridgeStore(bridge: CerebralBridge, initialState: DashboardState): DashboardStore {
  let state = initialState;
  const listeners = new Set<() => void>();

  bridge.subscribe((event) => {
    const next = reduceDashboardState(state, event);
    if (next === state) {
      return;
    }
    state = next;
    // Snapshot so a listener that unsubscribes mid-dispatch can't mutate the live set.
    for (const listener of [...listeners]) {
      listener();
    }
  });

  return {
    getState: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    }
  };
}
