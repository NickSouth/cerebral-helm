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
  | "bridge.capability.changed";

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

export interface RecentActivityQuery {
  readonly limit?: number;
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
  /** Subscribe to the bridge event stream; returns an unsubscribe handle. */
  subscribe(listener: BridgeEventListener): Unsubscribe;
}
