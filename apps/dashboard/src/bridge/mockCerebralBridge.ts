import type { DashboardBootstrapState } from "./types";
import { getDashboardConfigBundle, getDashboardFixture } from "../fixtures/canonicalFixtures";

/**
 * Compose a full bootstrap state from the eager config bundle (all four mode views +
 * agent roster) and the active mode's per-state snapshot — the shape the real bridge
 * delivers (eager config, on-switch region data). NIC-52 replaces this static
 * composition with an event-driven MockCerebralBridge without changing consumers.
 */
export function loadBootstrapState(): DashboardBootstrapState {
  return {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture("mode.developer.ready")
  };
}
