import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { createBridgeStore } from "./bridgeStore";
import { failureStateFixtures } from "../fixtures/canonicalFixtures";
import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { DashboardStore } from "./dashboardState";

/**
 * How a friendly `?state=` name maps onto a canonical seed (NIC-64). Lets the owner preview each
 * degraded state via HMR (e.g. `?state=offline`) and gives tests a single, honest entry point —
 * the same canonical fixtures the mock composes, never a bespoke mock path. `recovery` has no
 * dashboardState (it is a runtime-folded posture), so it seeds ready then emits the canonical
 * `bridge_failure` status event.
 */
const STATE_PRESETS: Readonly<Record<string, { bootstrapKey?: string; recovery?: boolean }>> = {
  ready: {},
  offline: { bootstrapKey: "failure.dashboard_offline" },
  loading: { bootstrapKey: "system.dashboard.loading" },
  error: { bootstrapKey: "failure.dashboard_error" },
  recovery: { recovery: true }
};

/** Emit the canonical read-only recovery status event so the reducer folds in the recovery posture. */
function emitRecovery(bridge: ReturnType<typeof createMockCerebralBridge>): void {
  const fixture = failureStateFixtures.find((f) => f.canonicalKey === "failure.bridge_major_version_mismatch");
  if (!fixture) {
    return;
  }
  bridge.emit({
    eventId: `brevt_${fixture.id}`,
    type: "system.status.changed",
    schemaVersion: "1.0.0",
    timestamp: fixture.clock,
    payload: { canonicalKey: fixture.canonicalKey, category: fixture.category, state: fixture.state }
  });
}

/**
 * The dashboard's runtime (NIC-52 B2 + D2): a MockCerebralBridge plus the event-driven store
 * built over it. The store seeds synchronously from the canonical bootstrap composition (the
 * default mode — Executive, ADR-007) and folds the bridge's event stream into state. The
 * native WKWebView transport swaps the bridge without touching consumers. An optional `stateName`
 * (from `?state=`) seeds a degraded state for preview/tests (NIC-64).
 */
export function createDashboardRuntime(options: { stateName?: string } = {}): {
  bridge: CerebralBridge;
  store: DashboardStore;
} {
  const preset = (options.stateName && STATE_PRESETS[options.stateName]) || STATE_PRESETS.ready;
  const bridge = createMockCerebralBridge({ bootstrapKey: preset.bootstrapKey });
  const store = createBridgeStore(bridge, loadBootstrapState(preset.bootstrapKey));
  if (preset.recovery) {
    emitRecovery(bridge);
  }
  return { bridge, store };
}

/** Read the requested preview state from the URL (`?state=offline` etc.); undefined if absent. */
export function readStateNameFromLocation(): string | undefined {
  if (typeof window === "undefined" || !window.location?.search) {
    return undefined;
  }
  const value = new URLSearchParams(window.location.search).get("state");
  return value ?? undefined;
}
