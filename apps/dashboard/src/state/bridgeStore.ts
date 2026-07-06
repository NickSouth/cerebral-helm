import type { BridgeEvent, CerebralBridge } from "../bridge/cerebralBridge";
import type {
  ConfirmationDisclosure,
  DashboardStateSnapshot,
  HeimlichState,
  RegionState,
  SystemHealthRegion
} from "../bridge/types";
import type { DashboardState, DashboardStore, WorkflowRunProgress } from "./dashboardState";

/** One channel of the native status publisher's `system_metrics` payload (NIC-81b). */
interface MetricsChannelPayload {
  readonly availability?: string;
  readonly value?: number | null;
  readonly sampledAt?: string | null;
}

interface MetricsNetworkPayload {
  readonly availability?: string;
  readonly uploadMbps?: number | null;
  readonly downloadMbps?: number | null;
  readonly sampledAt?: string | null;
}

interface MetricsBatteryPayload extends MetricsChannelPayload {
  readonly charging?: boolean | null;
  readonly pluggedIn?: boolean | null;
}

interface SystemMetricsPayload {
  readonly cpu?: MetricsChannelPayload;
  readonly memory?: MetricsChannelPayload;
  readonly network?: MetricsNetworkPayload;
  readonly battery?: MetricsBatteryPayload;
  readonly display?: MetricsChannelPayload;
}

/**
 * Adapter availability → region state. `loading` maps to "empty" (no number to
 * show yet, honestly); `disconnected` renders as stale so the last value is
 * visibly out of date rather than silently wrong.
 */
function channelState(availability: string | undefined): RegionState {
  switch (availability) {
    case "available":
      return "ready";
    case "stale":
    case "disconnected":
      return "stale";
    case "loading":
      return "empty";
    default:
      return "unavailable";
  }
}

/** Fold one live metrics snapshot into the system-health region shape. */
function systemHealthFromMetrics(payload: SystemMetricsPayload): SystemHealthRegion {
  const cpuLive = payload.cpu?.availability === "available";
  const memoryLive = payload.memory?.availability === "available";
  const networkState = channelState(payload.network?.availability);
  const batteryState = channelState(payload.battery?.availability);
  return {
    state: "ready",
    cpuPercent: cpuLive ? (payload.cpu?.value ?? undefined) : undefined,
    memoryPercent: memoryLive ? (payload.memory?.value ?? undefined) : undefined,
    network: {
      state: networkState,
      label: "Network",
      uploadMbps: payload.network?.uploadMbps ?? undefined,
      downloadMbps: payload.network?.downloadMbps ?? undefined
    },
    battery: {
      state: batteryState,
      label: "Battery",
      percent: batteryState === "ready" ? (payload.battery?.value ?? undefined) : undefined,
      charging: batteryState === "ready" ? (payload.battery?.charging ?? undefined) : undefined,
      pluggedIn: batteryState === "ready" ? (payload.battery?.pluggedIn ?? undefined) : undefined
    }
  };
}

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
 * nothing changes, so useSyncExternalStore does not trigger a needless re-render.
 */
export function reduceDashboardState(state: DashboardState, event: BridgeEvent): DashboardState {
  switch (event.type) {
    case "confirmation.changed": {
      // A policy-owned confirmation arrived (a disclosure) or was resolved/invalidated (null).
      // Runtime-only state — never folded into the bootstrap config (NIC-62).
      const next =
        (event.payload as { confirmation?: ConfirmationDisclosure | null }).confirmation ?? null;
      const current = state.activeConfirmation ?? null;
      if (next === current) {
        return state;
      }
      return { ...state, activeConfirmation: next };
    }
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
      // A terminal command ends any live workflow-run progress (NIC-85).
      const terminal = status === "succeeded" || status === "failed" || status === "cancelled";
      const clearedRun = terminal && state.activeWorkflowRun ? null : state.activeWorkflowRun;
      const next = LIFECYCLE_TO_HEIMLICH[status];
      if ((!next || next === state.heimlich.state) && clearedRun === state.activeWorkflowRun) {
        return state;
      }
      return {
        ...state,
        heimlich: next ? { ...state.heimlich, state: next } : state.heimlich,
        activeWorkflowRun: clearedRun
      };
    }
    case "workflow.action.progress": {
      // One step of an executing quick action started or finished (NIC-85).
      // Runtime-only state — never folded into the bootstrap config.
      const payload = event.payload as Partial<WorkflowRunProgress>;
      if (!payload.workflowId || !payload.actionId || !payload.status) {
        return state;
      }
      return {
        ...state,
        activeWorkflowRun: {
          commandId: String(payload.commandId ?? ""),
          workflowId: payload.workflowId,
          actionId: payload.actionId,
          kind: String(payload.kind ?? ""),
          status: payload.status,
          index: Number(payload.index ?? 0),
          total: Number(payload.total ?? 0),
          message: payload.message
        }
      };
    }
    case "bridge.capability.changed": {
      const capability = (
        event.payload as {
          capability?: { id?: string; available?: boolean; degradedReason?: string | null };
        }
      ).capability;
      if (!capability?.id || typeof capability.available !== "boolean") {
        return state;
      }
      // Fold the capability into the availability map native-gated controls read
      // (FR-SHL-06): the handshake set is replayed through this same event type,
      // and runtime permission rechecks (NIC-83) update it live.
      let next: DashboardState = {
        ...state,
        capabilities: {
          ...state.capabilities,
          [capability.id]: {
            available: capability.available,
            degradedReason: capability.degradedReason ?? null
          }
        }
      };
      // Losing live metrics additionally marks system health stale.
      const metricsDown = capability.id === "system.metrics" && capability.available === false;
      if (metricsDown && next.regions.systemHealth.state !== "stale") {
        next = {
          ...next,
          regions: {
            ...next.regions,
            systemHealth: { ...next.regions.systemHealth, state: "stale" }
          }
        };
      }
      return next;
    }
    case "system.status.changed": {
      const payload = event.payload as { category?: string; state?: Record<string, unknown> };
      // A live metrics snapshot from the native status publisher (NIC-81b): fold the
      // per-channel readings into the system-health region. Runtime-only state — never
      // folded into the bootstrap config.
      if (payload.category === "system_metrics") {
        return {
          ...state,
          regions: {
            ...state.regions,
            systemHealth: systemHealthFromMetrics(event.payload as SystemMetricsPayload)
          }
        };
      }
      // Bridge-failure posture (NIC-64): an incompatible bridge major version forces
      // read-only recovery, suppressing every mutating control via the posture seam.
      if (payload.category !== "bridge_failure" || payload.state?.status !== "read_only") {
        return state;
      }
      const reason = String(payload.state.message ?? "Bridge is in read-only recovery.");
      if (state.recovery?.reason === reason) {
        return state;
      }
      return { ...state, recovery: { reason, startupMode: "recovery" } };
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
export function createBridgeStore(
  bridge: CerebralBridge,
  initialState: DashboardState
): DashboardStore {
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
