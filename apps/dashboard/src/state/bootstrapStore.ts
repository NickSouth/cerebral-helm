import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { createBridgeStore } from "./bridgeStore";
import type { CerebralBridge } from "../bridge/cerebralBridge";
import type { DashboardStore } from "./dashboardState";

/**
 * The dashboard's runtime (NIC-52 B2 + D2): a MockCerebralBridge plus the event-driven store
 * built over it. The store seeds synchronously from the canonical bootstrap composition (the
 * default mode — Executive, ADR-007) and folds the bridge's event stream into state. The
 * native WKWebView transport swaps the bridge without touching consumers.
 */
export function createDashboardRuntime(): { bridge: CerebralBridge; store: DashboardStore } {
  const bridge = createMockCerebralBridge();
  const store = createBridgeStore(bridge, loadBootstrapState());
  return { bridge, store };
}
