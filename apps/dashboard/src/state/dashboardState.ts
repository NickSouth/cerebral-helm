import type { ConfirmationDisclosure, DashboardBootstrapState, DashboardMode } from "../bridge/types";

export type { DashboardMode };

/**
 * The slice of dashboard state the UI renders: the bootstrap snapshot plus runtime-only state
 * folded in from the bridge event stream. `activeConfirmation` is the policy-owned confirmation
 * disclosure delivered by `confirmation.changed` (NIC-62) — absent until one arrives, and never
 * part of the static bootstrap config.
 */
export type DashboardState = DashboardBootstrapState & {
  readonly activeConfirmation?: ConfirmationDisclosure | null;
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
