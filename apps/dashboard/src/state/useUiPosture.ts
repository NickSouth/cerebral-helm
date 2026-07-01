import type { DashboardUiState } from "../bridge/types";
import type { DashboardState } from "./dashboardState";
import { useDashboardState } from "./DashboardStateProvider";

/**
 * The derived degraded-state posture (NIC-64) — the single source every top-level treatment
 * and every mutating control reads, so read-only recovery is enforced in one place rather than
 * re-derived per component (FR-UI-07, FR-SHL-05).
 */
export interface UiPosture {
  readonly uiState: DashboardUiState;
  /** First-paint: data has not arrived yet — render a skeleton, never a blank screen. */
  readonly loading: boolean;
  /** The dashboard is showing last-known-safe data; live capabilities are unreachable. */
  readonly offline: boolean;
  /** A top-level error the user can act on with a specific recovery affordance. */
  readonly error: boolean;
  /** Startup entered read-only recovery (e.g. an incompatible bridge major version). */
  readonly recovering: boolean;
  /**
   * The surface must not expose mutating controls. True whenever offline or recovering — both
   * are read-only postures; write controls (mode switch, quick actions, command submit,
   * confirmation approve) are suppressed.
   */
  readonly readOnly: boolean;
  /** Any non-ready top-level posture (loading/offline/error/recovering). */
  readonly degraded: boolean;
  /** The specific recovery reason when recovering; used by the recovery banner copy. */
  readonly recoveryReason: string | null;
}

/**
 * Fold `uiState` + the runtime `recovery` widening into a `UiPosture`. Pure so it is unit-tested
 * without React. `readOnly` is deliberately the union of offline and recovering — the two states
 * where a write would be dishonest.
 */
export function deriveUiPosture(state: DashboardState): UiPosture {
  const uiState = state.uiState;
  const recovery = state.recovery ?? null;
  const loading = uiState === "loading";
  const offline = uiState === "offline";
  const error = uiState === "error";
  const recovering = recovery !== null;
  const readOnly = offline || recovering;
  return {
    uiState,
    loading,
    offline,
    error,
    recovering,
    readOnly,
    degraded: loading || offline || error || recovering,
    recoveryReason: recovery?.reason ?? null
  };
}

/** Hook form of {@link deriveUiPosture}, read through the store seam. */
export function useUiPosture(): UiPosture {
  return deriveUiPosture(useDashboardState());
}
