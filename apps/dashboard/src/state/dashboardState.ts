import type { ConfirmationDisclosure, DashboardBootstrapState, DashboardMode } from "../bridge/types";

export type { DashboardMode };

/**
 * Read-only recovery posture (NIC-64). Delivered at runtime via `system.status.changed`
 * (a `bridge_failure`/`read_only` startup outcome) — never part of the static bootstrap
 * config. Its presence forces the whole surface read-only: no mutating control may be
 * reachable while recovering (FR-SHL-05).
 */
export interface RecoveryPosture {
  /** The specific, user-facing reason startup entered recovery (drives the recovery banner). */
  readonly reason: string;
  readonly startupMode: "recovery";
}

/**
 * The slice of dashboard state the UI renders: the bootstrap snapshot plus runtime-only state
 * folded in from the bridge event stream. `activeConfirmation` is the policy-owned confirmation
 * disclosure delivered by `confirmation.changed` (NIC-62); `recovery` is the read-only recovery
 * posture delivered by `system.status.changed` (NIC-64). Both are absent until an event arrives
 * and are never part of the static bootstrap config (the runtime-only widening pattern).
 */
export type DashboardState = DashboardBootstrapState & {
  readonly activeConfirmation?: ConfirmationDisclosure | null;
  readonly recovery?: RecoveryPosture | null;
};

/**
 * The state-boundary seam. Components depend on this contract, never on a concrete
 * loader or bridge. NIC-52 B2 implements it over MockCerebralBridge + the event store;
 * `subscribe` lets the provider re-render via useSyncExternalStore when events arrive.
 */
export interface DashboardStore {
  getState(): DashboardState;
  /** Register a change listener; returns an unsubscribe handle. */
  subscribe(listener: () => void): () => void;
}
