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
  | "settings.changed"
  | "bridge.capability.changed"
  | "workflow.action.progress"
  | "display.topology.changed"
  | "layout.session.changed"
  | "mode.windowcollapse.changed"
  | "widget.data.changed";

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
    /** The display layout mode opens on (and whose bottom bar shows the hotswap pill).
     *  `system-primary` sentinel when unset (NIC-142). */
    readonly layoutDisplayId: string;
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

/** A configured URL reference (NIC-146): a web address the user can open by id and
 *  pin as a quick app, the same way an app reference works. `target` is always an
 *  http/https URL. */
export interface UrlReference {
  readonly id: string;
  readonly label: string;
  readonly target: string;
  /** The site's favicon as a base64 PNG (NIC-147), fetched and cached by the host.
   *  Absent until the fetch lands — the tile shows a globe placeholder meanwhile and
   *  upgrades live when a `mode.quickapps.changed` event prompts a re-read. */
  readonly iconPng?: string;
  /** The Google Chrome profile the reference opens in (NIC-151), when configured;
   *  absent for the default open behavior. */
  readonly profile?: string;
}
export interface AddUrlReferenceInput {
  readonly url: string;
  /** Optional display label; defaults to the URL's host when omitted. */
  readonly label?: string;
  /** Optional Google Chrome profile directory (`--profile-directory`, NIC-151); when
   *  set the minted URL opens in that Chrome profile. */
  readonly profile?: string;
}
export interface AddUrlReferenceResult {
  readonly accepted: boolean;
  /** The minted (or already-existing) reference when accepted; null on rejection. */
  readonly reference: UrlReference | null;
  readonly errors: readonly string[];
}
export interface ListUrlsResult {
  readonly urls: readonly UrlReference[];
}

/** A Google Chrome profile discovered on this machine (NIC-151). `directory` is the
 *  `--profile-directory` value a reference stores; `name` is the display name shown
 *  in the dropdown; `iconPng` is the account avatar (base64 PNG) when available. */
export interface ChromeProfile {
  readonly directory: string;
  readonly name: string;
  readonly iconPng?: string;
}
/** An app reference (NIC-151), e.g. a pinned Chrome profile: `target` is a bundle id
 *  and `profile` is the Chrome profile it opens in. */
export interface AppReference {
  readonly id: string;
  readonly label: string;
  readonly target: string;
  readonly profile?: string;
}
export interface ChromeProfilesResult {
  readonly profiles: readonly ChromeProfile[];
  /** The user's pinned Chrome-profile app references, so a pinned tile can resolve
   *  its label + avatar by matching `profile` back to a discovered profile. */
  readonly references: readonly AppReference[];
}
export interface AddChromeProfileInput {
  readonly directory: string;
  readonly name?: string;
}
export interface AddChromeProfileResult {
  readonly accepted: boolean;
  readonly reference: AppReference | null;
  readonly errors: readonly string[];
}

// --- Layout mode (NIC-142) ---

/** One window in an active layout session: an app or URL reference the layout put on
 *  screen, addressed by its configured reference id. `label` is the reference's human
 *  name, for the bottom-bar chip. */
export interface LayoutSessionWindow {
  readonly ref: string;
  readonly kind: "app" | "url";
  readonly label: string;
}
/** The single dynamic quick-toggle slot: `activeRef` is the target currently shown;
 *  `targets` are the windows the slot can swap between (the swap itself lands in a
 *  later increment). */
export interface LayoutSessionToggle {
  readonly activeRef: string;
  readonly targets: readonly LayoutSessionWindow[];
}
/** The active layout session (NIC-142), delivered by `layout.session.changed`. The
 *  bottom-bar layout section renders from this; it is null when no layout is active. */
export interface LayoutSession {
  readonly modeId: string;
  readonly windows: readonly LayoutSessionWindow[];
  readonly quickToggle: LayoutSessionToggle | null;
}
export interface OpenLayoutInput {
  readonly modeId: string;
}
export interface OpenLayoutResult {
  readonly accepted: boolean;
  readonly modeId: string;
}
export interface CloseLayoutResult {
  readonly closed: boolean;
}
export interface ToggleLayoutInput {
  readonly ref: string;
}
export interface ToggleLayoutResult {
  readonly accepted: boolean;
}
export interface PinLayoutWindowInput {
  readonly modeId: string;
  readonly ref: string;
}
export interface PinLayoutWindowResult {
  readonly accepted: boolean;
  readonly errors: readonly string[];
}
/** Add a reference to the ACTIVE layout session's dynamic slot for this session only
 *  (NIC-142) — the bottom-bar "+" live add. Unlike {@link PinLayoutWindowInput} it does
 *  not persist to the mode override; the target is gone when layout mode closes. */
export interface AddLayoutTargetInput {
  readonly ref: string;
}
export interface AddLayoutTargetResult {
  readonly accepted: boolean;
}

// --- Window management: collapse / expand all (NIC-143) ---

export interface ToggleModeCollapseInput {
  readonly modeId: string;
}
/** The mode's collapse-all state after the toggle: `collapsed` true when its windows
 *  are now hidden in the session bucket, false when they have been returned. */
export interface ToggleModeCollapseResult {
  readonly collapsed: boolean;
}

// --- Window navigator (NIC-143) ---

/** One open window in the navigator inventory. `id` is opaque (the stringified
 *  CGWindowID on macOS) — pass it back to act on the window, never parse it. */
export interface NavigatorWindow {
  readonly id: string;
  readonly title: string;
  readonly minimized: boolean;
}
/** One application's open windows, grouped for the navigator's app-stacked cards. */
export interface NavigatorWindowGroup {
  readonly bundleId: string;
  readonly appName: string;
  /** The app's icon as a base64 PNG for the card mark; absent when unavailable
   *  (the card falls back to a category glyph). */
  readonly appIconPng?: string;
  readonly windows: readonly NavigatorWindow[];
}
/** Every open window on screen, grouped by application (NIC-143). */
export interface WindowInventory {
  readonly apps: readonly NavigatorWindowGroup[];
}
export interface WindowRefInput {
  readonly windowId: string;
}
/** Whether a minimize/surface/close action found its window and took effect. */
export interface WindowActionResult {
  readonly ok: boolean;
}

/** The named window frames (mirrors `window-arrange-input` / the layout schema). */
export type LayoutFrame =
  | "full"
  | "left-half"
  | "right-half"
  | "top-half"
  | "bottom-half"
  | "left-two-thirds"
  | "right-third"
  | "left-third"
  | "right-two-thirds"
  | "centered";
export interface LayoutWindowSpec {
  readonly ref: string;
  readonly kind: "app" | "url";
  readonly frame: LayoutFrame;
}
export interface LayoutSpec {
  readonly display: "primary" | "secondary";
  readonly windows: readonly LayoutWindowSpec[];
  readonly quickToggle?: {
    readonly frame: LayoutFrame;
    readonly targets: readonly { readonly ref: string; readonly kind: "app" | "url" }[];
  };
}
export interface UpdateLayoutInput {
  readonly modeId: string;
  readonly layout: LayoutSpec;
}
export interface UpdateLayoutResult {
  readonly accepted: boolean;
  readonly errors: readonly string[];
}
/** One window proposed by live capture: a configured app snapped to a named frame. */
export interface CapturedWindow {
  readonly ref: string;
  readonly kind: "app" | "url";
  readonly frame: LayoutFrame;
}
export interface CaptureLayoutResult {
  readonly windows: readonly CapturedWindow[];
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
  /** Mint a user URL reference (NIC-146) so a typed URL can be pinned as a quick app,
   *  the same route apps take. Only http/https URLs mint; the returned reference id is
   *  the pinnable key passed to {@link updateQuickApps}. */
  addUrlReference(input: AddUrlReferenceInput): Promise<AddUrlReferenceResult>;
  /** The configured URL references (shipped + user-minted), so pinned URL tiles render
   *  with their real labels — the URL counterpart of {@link listApps} (NIC-146). */
  listUrls(): Promise<ListUrlsResult>;
  /** The user's Chrome profiles (NIC-151) for the profile dropdown + avatar badges,
   *  plus the pinned Chrome-profile references so their tiles resolve label + avatar. */
  listChromeProfiles(): Promise<ChromeProfilesResult>;
  /** Mint an app reference that opens Chrome in a specific profile (NIC-151), so a
   *  Chrome profile can be pinned as a quick app; the returned id is the pinnable key. */
  addChromeProfileReference(input: AddChromeProfileInput): Promise<AddChromeProfileResult>;
  /** Run an on-demand internet speed test (NIC-135). Resolves when the ~30s
   *  measurement completes; read-only, so it never gates on confirmation. */
  runSpeedTest(): Promise<SpeedTestResult>;
  /** Enter layout mode for a mode (NIC-142): start the bottom-bar layout session
   *  from the mode's authored layout and open its windows. The session arrives via
   *  a `layout.session.changed` event, not this result. */
  openLayout(input: OpenLayoutInput): Promise<OpenLayoutResult>;
  /** Exit layout mode: hide the layout's windows and clear the session (a null
   *  `layout.session.changed` follows). */
  closeLayout(): Promise<CloseLayoutResult>;
  /** Swap the layout's dynamic quick-toggle slot to a target (NIC-142): hides the
   *  previously-shown window and surfaces the pressed one. The updated session
   *  arrives via `layout.session.changed`. No confirmation — authorized at open. */
  toggleLayout(input: ToggleLayoutInput): Promise<ToggleLayoutResult>;
  /** Pin an app/URL reference as a new quick-toggle target on a mode's layout
   *  (NIC-142), persisted through the validated override path. The updated session
   *  arrives via `layout.session.changed`. */
  pinLayoutWindow(input: PinLayoutWindowInput): Promise<PinLayoutWindowResult>;
  /** Add a reference to the active layout session's dynamic slot for this session only
   *  (NIC-142) — the bottom-bar "+" live add. Non-persistent; the updated session
   *  arrives via `layout.session.changed`. */
  addLayoutTarget(input: AddLayoutTargetInput): Promise<AddLayoutTargetResult>;
  /** Save a full authored layout for a mode (NIC-142 authoring), persisted through
   *  the validated override path. */
  updateLayout(input: UpdateLayoutInput): Promise<UpdateLayoutResult>;
  /** Propose a layout from the currently-arranged windows (NIC-142 live capture),
   *  each visible configured app snapped to a named frame. macOS-only. */
  captureLayout(): Promise<CaptureLayoutResult>;
  /** Collapse or expand all of the current mode's windows (NIC-143): the first call
   *  hides the visible apps into the mode's session-only bucket, the next returns
   *  exactly them. Uses the same app-level hide as "Windows Stored by Mode"; not
   *  confirmation-gated. The bottom-bar icon also updates from a
   *  `mode.windowcollapse.changed` event (emitted here and on every mode switch). */
  toggleModeCollapse(input: ToggleModeCollapseInput): Promise<ToggleModeCollapseResult>;
  /** Close all windows across every mode (NIC-143): quit every open application
   *  except CerebralHelm. Destructive — routes through the command bus, so the
   *  policy engine gates it on a confirmation (delivered via `confirmation.changed`);
   *  the returned receipt only acknowledges the command was accepted for review. */
  closeAllWindows(): Promise<CommandReceipt>;
  /** List every open window, grouped by application, for the window navigator
   *  (NIC-143). Direct read — no confirmation; an honest empty inventory when the
   *  host cannot enumerate windows. */
  listWindows(): Promise<WindowInventory>;
  /** Minimize a single window to the Dock (NIC-143). Non-gated. */
  minimizeWindow(input: WindowRefInput): Promise<WindowActionResult>;
  /** Bring a single window to the front, un-minimizing if needed (NIC-143). Non-gated. */
  surfaceWindow(input: WindowRefInput): Promise<WindowActionResult>;
  /** Close a single window — the equivalent of its own close button (NIC-143).
   *  Classified `local_write`, so it runs without a per-press confirmation. */
  closeWindow(input: WindowRefInput): Promise<WindowActionResult>;
  /** Subscribe to the bridge event stream; returns an unsubscribe handle. */
  subscribe(listener: BridgeEventListener): Unsubscribe;
}
