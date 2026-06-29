import { loadBootstrapState } from "../bridge/mockCerebralBridge";
import type { DashboardStore } from "./dashboardState";

/**
 * Static, synchronous store seeded from the canonical bootstrap fixture — the
 * pre-bridge filler for the state-boundary seam. NIC-52 swaps it for a
 * MockCerebralBridge-backed, event-driven store.
 */
export function createBootstrapStore(): DashboardStore {
  const state = loadBootstrapState();
  return { getState: () => state };
}
