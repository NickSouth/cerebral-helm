import type {
  ConfirmationDisclosure,
  DashboardBootstrapState,
  DashboardMode
} from "../bridge/types";
import type { LayoutSession } from "../bridge/cerebralBridge";

export type { LayoutSession };

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
 * One native capability's reported availability (FR-SHL-06), folded from the
 * handshake's capability set (replayed by the transport as
 * `bridge.capability.changed` events) and from runtime permission rechecks
 * (NIC-83). Controls gate on this — honest-disabled when unavailable, never
 * fake-successful.
 */
export interface CapabilityAvailability {
  readonly available: boolean;
  readonly degradedReason?: string | null;
}

/**
 * Live progress of one executing workflow / quick action, folded from
 * `workflow.action.progress` events (FR-CMD-05, NIC-85). Carries the latest
 * step's status and position so a renderer can show "2 of 5 — app.open".
 * Cleared when the command reaches a terminal lifecycle status.
 */
export interface WorkflowRunProgress {
  readonly commandId: string;
  readonly workflowId: string;
  readonly actionId: string;
  /** The step's tool id. */
  readonly kind: string;
  readonly status: "running" | "succeeded" | "failed" | "unavailable" | "cancelled";
  /** 1-based position of this step in the plan. */
  readonly index: number;
  readonly total: number;
  readonly message?: string;
}

/**
 * One connected display (NIC-87, FR-SHL-06), folded from
 * `display.topology.changed` events. `id` is stable across reconnects only when
 * `stableIdentity` is true — an id the platform could not guarantee must never
 * be persisted or matched against stored preferences.
 */
export interface DisplayDescriptor {
  readonly id: string;
  readonly name: string;
  readonly frame: { readonly x: number; readonly y: number; readonly width: number; readonly height: number };
  readonly primary: boolean;
  readonly stableIdentity: boolean;
}

/**
 * The current display topology (NIC-87). The shell publishes a full snapshot at
 * startup and on every connect/disconnect/rearrange, so this is always the
 * complete current set — never a delta.
 */
export interface DisplayTopology {
  readonly displays: readonly DisplayDescriptor[];
  readonly primaryDisplayId?: string | null;
}

/**
 * The slice of dashboard state the UI renders: the bootstrap snapshot plus runtime-only state
 * folded in from the bridge event stream. `activeConfirmation` is the policy-owned confirmation
 * disclosure delivered by `confirmation.changed` (NIC-62); `recovery` is the read-only recovery
 * posture delivered by `system.status.changed` (NIC-64); `activeWorkflowRun` is the live
 * per-action progress of an executing quick action (NIC-85). All are absent until an event
 * arrives and are never part of the static bootstrap config (the runtime-only widening pattern).
 */
export type DashboardState = DashboardBootstrapState & {
  readonly activeConfirmation?: ConfirmationDisclosure | null;
  readonly recovery?: RecoveryPosture | null;
  readonly activeWorkflowRun?: WorkflowRunProgress | null;
  readonly capabilities?: Readonly<Record<string, CapabilityAvailability>>;
  readonly displayTopology?: DisplayTopology | null;
  /** The active layout session (NIC-142), folded from `layout.session.changed`.
   *  Drives the bottom-bar layout section; null/absent when no layout is open. */
  readonly layoutSession?: LayoutSession | null;
  /** Per-mode collapse-all state (NIC-143), keyed by mode id → collapsed, folded from
   *  `mode.windowcollapse.changed`. Session-only and sparse: a mode is absent until its
   *  first toggle, and every mode starts expanded. Drives the bottom-bar
   *  collapse/expand icon for the current mode. */
  readonly windowCollapse?: Readonly<Record<string, boolean>>;
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
