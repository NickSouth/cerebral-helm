import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { createBridgeStore } from "./bridgeStore";
import type { DashboardStore } from "./dashboardState";

/**
 * The dashboard's runtime store (NIC-52 B2): a MockCerebralBridge-backed, event-driven
 * store. It seeds synchronously from the canonical bootstrap composition, then folds the
 * bridge's event stream into state. This replaces the former static snapshot store; the
 * native WKWebView transport swaps the bridge without touching consumers.
 */
export function createBootstrapStore(): DashboardStore {
  return createBridgeStore(createMockCerebralBridge(), loadBootstrapState());
}
