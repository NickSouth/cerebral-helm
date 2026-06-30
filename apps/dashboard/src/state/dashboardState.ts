import type { DashboardBootstrapState, DashboardMode } from "../bridge/types";

export type { DashboardMode };

/**
 * The slice of dashboard state the UI renders. For this pre-bridge foundation it is
 * exactly the bootstrap snapshot; NIC-52 widens it (NIC-117 d) and makes it
 * event-driven without changing how consumers read it.
 */
export type DashboardState = DashboardBootstrapState;

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
