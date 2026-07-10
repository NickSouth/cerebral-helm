import type { DashboardBootstrapState } from "./types";

/**
 * The `CerebralBridge` is the single contract every dashboard component and the state
 * store depend on. It is **transport-agnostic** — the mock here and the future native
 * WKWebView transport are interchangeable implementations, so no component branches on
 * transport (NIC-52). Operation payload shapes mirror
 * `packages/contracts/fixtures/valid/bridge/operations`; event shapes mirror
 * `packages/contracts/schemas/bridge/event.schema.json`.
 */

export type BridgeEventType =
  | "command.lifecycle.transition"
  | "confirmation.changed"
  | "system.status.changed"
  | "config.changed"
  | "mode.quickapps.changed"
  | "bridge.capability.changed"
  | "workflow.action.progress"
  | "display.topology.changed";

export interface BridgeEvent {
  readonly eventId: string;
  readonly type: BridgeEventType;
  readonly schemaVersion: string;
  readonly timestamp: string;
  readonly payload: Readonly<Record<string, unknown>>;
}

export type BridgeEventListener = (event: BridgeEvent) => void;
export type Unsubscribe = () => void;

// --- Operation input/output (inner payloads; the transport wraps them in the envelope) ---

export interface SubmitCommandInput {
  readonly rawInput: string;
  readonly source: string;
}
export interface CommandReceipt {
  readonly commandId: string;
  readonly accepted: boolean;
}

export interface ApplyModeInput {
  readonly modeId: string;
}
export interface ApplyModeResult {
  readonly modeId: string;
  readonly status: "ok" | "error";
}

export interface CaptureNoteInput {
  readonly title: string;
  readonly body: string;
  readonly kind?: string;
}
export interface CaptureNoteResult {
  readonly noteId: string;
}

export interface SearchNotesInput {
  readonly text: string;
  readonly limit?: number;
}
export interface NoteSearchHit {
  readonly noteId: string;
  readonly title: string;
  readonly excerpt: string;
}
export interface SearchNotesResult {
  readonly results: readonly NoteSearchHit[];
}

export interface DecideConfirmationInput {
  readonly id: string;
  readonly decision: "approve" | "cancel";
}
export interface DecideConfirmationResult {
  readonly confirmationId: string;
  readonly decision: string;
}

export interface UpdateSettingsInput {
  readonly patch: Readonly<Record<string, unknown>>;
}
export interface UpdateSettingsResult {
  readonly accepted: boolean;
}

/** The effective durable settings, read on open so the settings UI initializes its
 *  controls from persisted state instead of hardcoded defaults (NIC-141). Every field
 *  is fully resolved — a stored value when set, otherwise the deterministic default.
 *  Mirrors `settings-snapshot.schema.json`. This is the read side of
 *  {@link UpdateSettingsInput}; it deliberately omits data that already has a delivery
 *  channel (quick apps, login item, live command-palette hotkey). Appearance density
 *  is not a live setting for now and is absent. */
export interface SettingsSnapshot {
  readonly schemaVersion: string;
  /** The default-mode setting (stored, else configured, else `executive`) — NOT the
   *  currently active mode. */
  readonly defaultModeId: string;
  /** When true, policy requires confirmation before every non-read-only action (the
   *  'Ask before all actions' tightening). Defaults to false. */
  readonly confirmAllActions: boolean;
  readonly appearance: {
    readonly reducedMotion: boolean;
    /** The assistant's display name across the dashboard; defaults to `Heimlich`. */
    readonly assistantName: string;
  };
  /** `rootReference` is null when no knowledge root has been chosen. */
  readonly knowledge: { readonly rootReference: string | null };
  readonly workspace: {
    readonly windowsStoredByMode: boolean;
    /** `system-primary` sentinel when unset. */
    readonly mainDisplayId: string;
  };
  /** Per-mode accent overrides keyed by design-token name (e.g. `executive.primary`) →
   *  `#rrggbb`. Sparse: a key is present only when customized; the client fills palette
   *  defaults for every un-overridden channel. */
  readonly modeColors: Readonly<Record<string, string>>;
}

export interface RecentActivityQuery {
  readonly limit?: number;
}

/** One installed application from read-only discovery (NIC-119). `iconPng` is a
 *  size-capped base64 PNG; absent means no icon could be rendered — the UI shows
 *  its honest placeholder glyph. */
export interface DiscoveredApp {
  readonly bundleId: string;
  readonly name: string;
  readonly iconPng?: string;
  /** The configured app reference this bundle id backs. Only reference-backed
   *  apps are pinnable (NIC-119c) — never arbitrary paths. */
  readonly referenceId?: string | null;
}
export interface ListAppsResult {
  readonly apps: readonly DiscoveredApp[];
  readonly truncated: boolean;
}

/** On-demand internet speed test result (NIC-135). `status` is "ok" (both
 *  directions), "partial" (one), or "unavailable" (the test could not run);
 *  figures are Mbps and present per `status`. */
export interface SpeedTestResult {
  readonly status: "ok" | "partial" | "unavailable";
  readonly downloadMbps?: number;
  readonly uploadMbps?: number;
  readonly testedAt?: string;
}

export interface UpdateQuickAppsInput {
  readonly modeId: string;
  readonly quickApps: readonly string[];
}
export interface UpdateQuickAppsResult {
  readonly accepted: boolean;
  readonly quickApps: readonly string[];
  readonly errors: readonly string[];
}

// --- FR-OBS-04 read surface (shape from get-recent-activity-response fixture) ---

export interface ActivityCommand {
  readonly id: string;
  readonly source: string;
  readonly status: string;
  readonly summary: string;
  readonly occurredAt: string;
}
export interface ActivityToolCall {
  readonly id: string;
  readonly commandId: string;
  readonly toolId: string;
  readonly adapterId: string;
  readonly status: string;
  readonly durationMs: number;
  readonly occurredAt: string;
}
export interface ActivityConfirmation {
  readonly confirmationId: string;
  readonly commandId: string;
  readonly decision: string;
  readonly occurredAt: string;
}
export interface ActivityModeSession {
  readonly id: string;
  readonly modeId: string;
  readonly result: string;
  readonly startedAt: string;
  readonly endedAt: string;
}
export interface ActivityError {
  readonly id: string;
  readonly category: string;
  readonly code: string;
  readonly message: string;
  readonly occurredAt: string;
}
export interface RecentActivity {
  readonly commands: readonly ActivityCommand[];
  readonly toolCalls: readonly ActivityToolCall[];
  readonly confirmations: readonly ActivityConfirmation[];
  readonly modeSessions: readonly ActivityModeSession[];
  readonly errors: readonly ActivityError[];
}

export interface CerebralBridge {
  getBootstrapState(): Promise<DashboardBootstrapState>;
  getRecentActivity(query?: RecentActivityQuery): Promise<RecentActivity>;
  submitCommand(input: SubmitCommandInput): Promise<CommandReceipt>;
  applyMode(input: ApplyModeInput): Promise<ApplyModeResult>;
  captureNote(input: CaptureNoteInput): Promise<CaptureNoteResult>;
  searchNotes(input: SearchNotesInput): Promise<SearchNotesResult>;
  decideConfirmation(input: DecideConfirmationInput): Promise<DecideConfirmationResult>;
  updateSettings(input: UpdateSettingsInput): Promise<UpdateSettingsResult>;
  /** Read the effective persisted settings so the settings UI initializes its
   *  controls from stored state instead of defaults (NIC-141). */
  getSettings(): Promise<SettingsSnapshot>;
  /** Read-only application discovery for the More Apps picker (NIC-119). */
  listApps(): Promise<ListAppsResult>;
  /** Set a mode's quick-app slots through the validated config-write path (NIC-119c). */
  updateQuickApps(input: UpdateQuickAppsInput): Promise<UpdateQuickAppsResult>;
  /** Run an on-demand internet speed test (NIC-135). Resolves when the ~30s
   *  measurement completes; read-only, so it never gates on confirmation. */
  runSpeedTest(): Promise<SpeedTestResult>;
  /** Subscribe to the bridge event stream; returns an unsubscribe handle. */
  subscribe(listener: BridgeEventListener): Unsubscribe;
}
