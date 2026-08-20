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
  | "widget.data.changed"
  | "weather.changed"
  | "news.changed"
  | "mail.changed"
  | "schedule.changed"
  | "system.checks.changed"
  | "apps.changed";

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

/** Input for {@link CerebralBridge.suggestCommands} (NIC-168). An empty query is
 *  valid — it lists the supported grammar. */
export interface SuggestCommandsInput {
  readonly query: string;
  readonly limit?: number;
}
/** One ranked, capability-aware candidate for the palette / launcher (NIC-168).
 *  `command` is always an exact string in the parser's grammar: executing a
 *  suggestion means submitting `command` verbatim — except `requiresArgument`
 *  rows, whose `command` is a fill-in prefix (`"note "`) that completes the
 *  input instead of executing. Unavailable rows render visibly disabled, never
 *  fake-successful (NIC-58, FR-UI-07). */
export interface SuggestedCommand {
  readonly command: string;
  readonly label: string;
  readonly detail?: string | null;
  readonly kind: "app" | "url" | "workflow" | "mode" | "hook" | "command" | "pattern";
  readonly requiresArgument: boolean;
  readonly available: boolean;
  readonly unavailableReason?: string | null;
}
export interface SuggestCommandsResult {
  readonly suggestions: readonly SuggestedCommand[];
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

/**
 * The `create-event` form's collected values. Times are LOCAL WALL-CLOCK ISO strings
 * (`2026-08-03T14:00`), matching the calendar read side — the time typed is the time meant.
 * `calendarTitle` rides along so a confirmation prompt can name the calendar in words.
 */
export interface CreateCalendarEventInput {
  readonly title: string;
  readonly startsAt: string;
  readonly endsAt: string;
  readonly calendarId?: string;
  readonly calendarTitle?: string;
  readonly location?: string;
  readonly notes?: string;
}
export interface CreateCalendarEventResult {
  /** The event id, or the pending command id when the action gated on confirmation. */
  readonly eventId: string;
  readonly calendarTitle?: string;
  /** True when a confirmation is now pending — never report "created" in that case. */
  readonly awaitingConfirmation: boolean;
}

export interface CloneRepositoryInput {
  readonly repositoryUrl: string;
  /** Optional folder under the projects root; the host derives one from the repository otherwise. */
  readonly directory?: string;
}
export interface CloneRepositoryResult {
  /** The cloned path, or the pending command id when the action gated on confirmation. */
  readonly clonedPath: string;
  readonly repositoryName: string;
  /** True when a confirmation is now pending — never report "cloned" in that case. */
  readonly awaitingConfirmation: boolean;
}

/**
 * What a native folder picker returned (quick actions phase 4). `relativeFolder` is the selection
 * relative to the projects root — `""` for the root itself. `outsideRoot` is a refused selection,
 * which is a different fact from `cancelled`: one deserves an explanation, the other silence.
 * `available: false` means the host has no picker at all, so the form falls back to typing.
 */
export interface ChooseFolderResult {
  readonly folderPath: string | null;
  readonly relativeFolder: string | null;
  readonly cancelled: boolean;
  readonly outsideRoot: boolean;
  readonly available: boolean;
}

/** One Linear team and the projects/labels scoped to it (quick actions phase 4). Nested rather
 *  than flattened: a project belongs to exactly one team, and a flat list would let the form offer
 *  one from another team, which Linear rejects at write time. */
export interface LinearOption {
  readonly id: string;
  readonly name: string;
}
export interface LinearTeam {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly projects: readonly LinearOption[];
  readonly labels: readonly LinearOption[];
}
export interface ListLinearOptionsResult {
  readonly teams: readonly LinearTeam[];
  /** False on a host with no Linear client at all — different from an empty workspace. */
  readonly available: boolean;
  /** Present when the workspace could not be read, so the form says so rather than rendering
   *  empty dropdowns that look like the user has no teams. */
  readonly reason: string | null;
}

/** One workflow state as Linear defines it (NIC-221). */
export interface LinearIssueState {
  readonly name: string;
  /** `backlog` | `unstarted` | `started` | `completed` | `canceled`. The only stable thing to
   *  group on — a status NAME is the user's to rename, its type is not. */
  readonly type: string;
  /** Linear's own colour for the status, so the surface never invents a palette for statuses it
   *  does not own. */
  readonly color: string;
  readonly position: number;
}

/** One issue as the cycle list renders it (NIC-221). Carries no description by design. */
export interface LinearCycleIssue {
  readonly identifier: string;
  readonly title: string;
  /** Linear's own issue URL — the row opens this rather than composing one. */
  readonly url: string;
  /** Linear's scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low. */
  readonly priority: number;
  readonly estimate: number | null;
  readonly sortOrder: number;
  readonly state: LinearIssueState;
  readonly labels: readonly string[];
  /** Linear's handle (e.g. `nickrsouthey`), or null when unassigned — label it, don't draw it. */
  readonly assignee: string | null;
  /** Linear's initials (e.g. `NS`) — what an avatar draws. */
  readonly assigneeInitials: string | null;
}

export interface LinearCycle {
  readonly id: string;
  readonly number: number;
  /** Cycles are usually unnamed; fall back to `Cycle <number>`. */
  readonly name: string | null;
  /** ISO-8601. */
  readonly startsAt: string;
  readonly endsAt: string;
}

export interface GetLinearProjectCycleResult {
  /** The project's name as LINEAR spells it, or null when the descriptor's `linear_project`
   *  matches no project. Null must not be rendered as an empty cycle — it means the link is
   *  wrong, which is fixable, whereas an empty cycle means there is simply nothing to do. */
  readonly matchedProject: string | null;
  /** Linear's own URL for the matched project — never composed client-side from a name. */
  readonly matchedProjectUrl: string | null;
  /** The active cycle, or null when none is running — between cycles is a real state. */
  readonly cycle: LinearCycle | null;
  readonly issues: readonly LinearCycleIssue[];
  /** True when Linear had more issues than one page returned; say so rather than looking complete. */
  readonly truncated: boolean;
  /** False on a host with no Linear client at all — different from an empty cycle. */
  readonly available: boolean;
  /** Present when the read was attempted and failed. */
  readonly reason: string | null;
}

export interface CreateLinearIssueInput {
  readonly title: string;
  readonly description?: string;
  readonly teamId: string;
  /** Display names ride along so a confirmation can name the destination in words. */
  readonly teamName?: string;
  readonly projectId?: string;
  readonly projectName?: string;
  /** A list: a Linear issue routinely carries several labels. */
  readonly labelIds?: readonly string[];
  readonly labelNames?: readonly string[];
  /** Linear's scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low. */
  readonly priority?: number;
}
export interface CreateLinearIssueResult {
  /** The issue identifier, or the pending command id when the action gated on confirmation. */
  readonly identifier: string;
  readonly url: string | null;
  /** True when a confirmation is now pending — never report "created" in that case. */
  readonly awaitingConfirmation: boolean;
}

export interface CreateSpotifyPlaylistInput {
  readonly name: string;
  readonly description?: string;
  /** Absent means private — Spotify's own API defaults this to true, which is not a default worth
   *  inheriting when it publishes to someone's profile. */
  readonly isPublic?: boolean;
}
export interface CreateSpotifyPlaylistResult {
  /** The playlist id, or the pending command id when the action gated on confirmation. */
  readonly playlistId: string;
  readonly name: string;
  readonly url: string | null;
  /** Whether Spotify came forward at the new playlist — best-effort, never a failure. */
  readonly opened: boolean;
  readonly awaitingConfirmation: boolean;
  readonly needsReconnect: boolean;
}

export interface ScaffoldProjectInput {
  readonly name: string;
  /** Optional folder under the projects root; the host joins the name onto it. */
  readonly location?: string;
  readonly summary?: string;
  /** Ordering weight for the Projects widget (higher first). */
  readonly importance?: number;
}
export interface ScaffoldProjectResult {
  /** The created folder's path, or the pending command id when the action gated. */
  readonly projectPath: string;
  readonly awaitingConfirmation: boolean;
}

/** One side of a team game. `color` is bare hex with no leading `#`, as the provider sends it. */
export interface SportsCompetitor {
  readonly abbreviation: string;
  readonly name: string;
  readonly score: string;
  readonly color: string | null;
  readonly isHome: boolean;
  readonly record: string | null;
}
/** One row of an individual-event leaderboard. `position` is empty on a finished event. */
export interface SportsLeaderboardEntry {
  readonly order: number;
  readonly position: string | null;
  readonly name: string;
  readonly score: string;
  readonly thru: string | null;
}
/** A game or tournament. `competitors` is filled for a team sport, `leaderboard` for an individual
 *  one — they differ in which collection is populated, not in shape. */
export interface SportsEvent {
  readonly id: string;
  readonly league: string;
  readonly name: string;
  readonly shortName: string;
  readonly state: "pre" | "in" | "post";
  readonly detail: string;
  /** Where it is played, when the source says. NFL supplies a stadium; golf carries no course. */
  readonly venue?: string | null;
  readonly competitors: readonly SportsCompetitor[];
  readonly leaderboard: readonly SportsLeaderboardEntry[];
}
export interface ListSportsEventsResult {
  readonly events: readonly SportsEvent[];
  /** False on a host with no sports provider — different from "nothing is on today". */
  readonly available: boolean;
  /** Present when the read failed, so the picker says so rather than showing an empty list. */
  readonly reason: string | null;
}

/** Someone (or some thread) a message can go to. `groupSize` is present only for a real group. */
export interface MessageRecipient {
  readonly id: string;
  readonly name: string;
  readonly kind: "participant" | "chat";
  readonly groupSize: number | null;
  readonly handle: string | null;
}
export interface ListMessageRecipientsResult {
  readonly recipients: readonly MessageRecipient[];
  readonly available: boolean;
  readonly reason: string | null;
}

export interface SendMessageInput {
  readonly body: string;
  readonly target: string;
  readonly targetKind: "participant" | "chat";
  /** Carried so the confirmation names who this is going to, rather than a phone number. */
  readonly targetName?: string;
  readonly groupSize?: number;
}
export interface SendMessageResult {
  readonly targetName: string;
  readonly sent: boolean;
  /** True on the normal path — this action always confirms before sending. */
  readonly awaitingConfirmation: boolean;
}

export interface SearchNotesInput {
  readonly text: string;
  readonly limit?: number;
}
export interface NoteSearchHit {
  readonly noteId: string;
  readonly title: string;
  readonly excerpt: string;
  /** The note's root-relative path (quick actions phase 5): the key the `search-notes` picker
   *  merges the file listing and the index on, and the handle it opens by. `noteId` cannot do
   *  that job — a note authored outside CerebralHelm has no frontmatter id. Optional because an
   *  index written before this field existed has none, and a hit without one is skipped rather
   *  than rendered as a row that would fail on click. */
  readonly path?: string;
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
  /** The user's tracked stock symbols for the Executive Stocks widget (NIC-128), in
   *  display order. Fully resolved: the stored list, else the shipped starter list. An
   *  empty array is a meaningful "cleared" state (the widget shows its empty prompt). */
  readonly stocks: { readonly tickers: readonly string[] };
  /** The user's calendar→mode mapping for the Today panel's per-mode relevance filtering
   *  (NIC-126), keyed by calendar identifier → mode id. Sparse: a calendar is present only when
   *  the user has mapped it; an unmapped calendar's events fall to the default mode (Executive). */
  readonly calendarModeMap: Readonly<Record<string, string>>;
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

/** One of the user's calendars (NIC-126) for the Settings calendar→mode mapping. `colorHex` is the
 *  calendar's colour for a swatch when known. */
export interface CalendarInfo {
  readonly id: string;
  readonly title: string;
  readonly colorHex?: string;
}
export interface ListCalendarsResult {
  /** Whether Calendar access is granted; false → the UI shows a "grant Calendar access" prompt
   *  and `calendars` is empty (never fabricated). */
  readonly authorized: boolean;
  readonly calendars: readonly CalendarInfo[];
}

/** The Canvas ingest connection state (NIC-132) for the Settings connect card. `available` is false
 *  only off the macOS host (the card then shows "requires the macOS host"). Otherwise `endpoint` and
 *  `token` are what the Chrome extension pairs with, and `lastScrapedAt` (ISO-8601, null until the
 *  first scrape) + the counts summarise the latest scrape. `token` is a local pairing secret. */
/** One scraped Canvas item in the Settings manage-list (NIC-132): its id, a display label, and
 *  whether the user has hidden it from the School widgets. */
export interface CanvasStatusItem {
  readonly id: string;
  readonly label: string;
  readonly hidden: boolean;
}

export interface CanvasStatus {
  readonly available: boolean;
  readonly endpoint: string;
  readonly token: string | null;
  readonly lastScrapedAt: string | null;
  /** Visible totals (hidden items excluded). */
  readonly courseCount: number;
  readonly deadlineCount: number;
  /** Every scraped course/assignment (hidden ones flagged) for the manage-list. */
  readonly courses: readonly CanvasStatusItem[];
  readonly deadlines: readonly CanvasStatusItem[];
}

/** One note in the Setup → Library card (NIC-162), projected from its Markdown file. `path` is
 *  relative to the knowledge root and `folder` is its containing folder (`inbox`, `projects/atlas`),
 *  empty at the root. `updated` is ISO-8601, or null when neither the note's frontmatter nor the
 *  file's date is readable. */
export interface NoteListItem {
  readonly path: string;
  readonly title: string;
  readonly folder: string;
  readonly updated: string | null;
}

/** The durable notes under the knowledge root (NIC-162). `available` is false when the root could
 *  not be read at all — the card then says so, because "no notes yet" and "your knowledge root is
 *  gone" must never look the same. `total` counts every note under the root regardless of the
 *  requested limit, so a card showing the most recent few still reports the real size. */
export interface ListNotesResult {
  readonly available: boolean;
  readonly root: string;
  readonly total: number;
  readonly notes: readonly NoteListItem[];
}

/** The unread-mail channel (Gmail integration), folded from `mail.changed`.
 *
 *  `unread` is **optional and absent unless it was actually measured** — the one thing that keeps
 *  this honest. Zero unread and "not connected" are completely different facts, and a surface that
 *  rendered both as 0 would tell you your inbox is clear when nobody has looked. */
export interface MailChannel {
  readonly state: "ready" | "not-connected" | "reconnect" | "unavailable";
  readonly unread?: number | null;
  /** True when counting stopped at a ceiling: there are **at least** `unread`. Rendered as "100+",
   *  never as a precise number the host never measured. */
  readonly unreadCapped?: boolean;
  /** Which slice was counted: `primary` (personal mail, promotions and the other category tabs
   *  excluded) or the whole `inbox` when the account does not categorize. The surface says which,
   *  because the two numbers differ enormously and "12 unread" would be false for an inbox with
   *  340 waiting. */
  readonly unreadScope?: "primary" | "inbox" | null;
  readonly reason?: string | null;
}

/** One unread message as the report renders it. `messageId` is the RFC 5322 Message-ID — the
 *  handle `open-mail` takes. Absent when the sender omitted one, in which case the row is text
 *  rather than a link. */
export interface UnreadMailItem {
  readonly id: string;
  readonly byline: string;
  readonly subject: string;
  readonly receivedAt?: string | null;
  readonly messageId?: string | null;
}
/** `state` is what separates "your inbox is clear" from "we could not look" — an empty array
 *  alone cannot, and rendering both as an empty report would claim you are caught up. */
export interface UnreadMailResult {
  readonly state: "ready" | "not-connected" | "reconnect" | "unavailable";
  readonly messages: readonly UnreadMailItem[];
  readonly reason?: string | null;
}

export interface ConnectGmailInput {
  readonly disconnect?: boolean;
}
/** The outcome of connecting Gmail. `canRefresh` false means the grant CANNOT renew itself — it
 *  works for an hour and then stops — so the surface reports it as a problem rather than a
 *  successful connection. */
export interface ConnectGmailResult {
  readonly connected: boolean;
  readonly scope: string | null;
  readonly canRefresh: boolean;
}

/** The receipt for starting a health run. It deliberately carries no results — a payload that
 *  looked like results would invite a caller to read the first snapshot as the answer. `started`
 *  is false on a host with no checks to run (the browser preview). */
export interface RunSystemChecksResult {
  readonly started: boolean;
  readonly checkCount: number;
}

/** One health check's current state, streamed on `system.checks.changed`. `skipped` is NOT a
 *  failure: a check the user never configured, or one held back because probing would spend a
 *  small daily quota, is neither passing nor broken. */
export interface SystemCheck {
  readonly id: string;
  readonly title: string;
  readonly group: "permissions" | "integrations" | "storage";
  readonly state: "pending" | "running" | "passed" | "failed" | "skipped";
  readonly detail?: string | null;
  /** The one step that would fix a failure, where there is one. */
  readonly remediation?: string | null;
  readonly durationMs?: number | null;
}

export interface SystemChecksPayload {
  readonly checks: readonly SystemCheck[];
  /** True once nothing is pending — the surface can stop saying "checking". */
  readonly complete: boolean;
  readonly failureCount: number;
}

/** One course notebook (quick actions phase 5). `folder` is root-relative, so it can be compared
 *  directly to a note listing's `folder` — which is how the picker's second stage finds a course's
 *  notes without a second read. */
export interface CourseFolder {
  readonly course: string;
  readonly folder: string;
  readonly noteCount: number;
  readonly updated: string | null;
}

/** The courses on disk. `available` is false when the knowledge root could not be read at all —
 *  "no courses yet" and "your vault is gone" must never look the same. */
export interface ListCoursesResult {
  readonly available: boolean;
  /** The root-relative school folder the courses came from. */
  readonly root: string;
  readonly courses: readonly CourseFolder[];
}

export interface CreateCourseNoteInput {
  readonly course: string;
  readonly title: string;
}

/** The created note. `path` is the same handle `notes-open` takes, so the picker can open what it
 *  just created — except while `awaitingConfirmation`, where nothing has been written yet. */
export interface CreateCourseNoteResult {
  readonly course: string;
  readonly path: string;
  readonly title: string;
  /** False when a note of that title already existed for that day and was returned rather than
   *  overwritten. Creating a note never clobbers one. */
  readonly created: boolean;
  readonly awaitingConfirmation: boolean;
}

/** The outcome of rebuilding the derived note search index (NIC-163). `rebuilt` is false only when
 *  the host has no knowledge composition (the browser preview) — the card then shows the action as
 *  unavailable rather than reporting a rebuild that never ran. Otherwise `root` is the knowledge
 *  root that was read and `noteCount` is how many notes were indexed. The durable Markdown is never
 *  written: a rebuild only reconstructs derived state. */
export interface KnowledgeRebuildResult {
  readonly rebuilt: boolean;
  readonly root: string;
  readonly noteCount: number;
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

/** Provision an API credential into the Keychain behind a logical reference (NIC-134). The
 *  `value` is the live secret — it is written to the secret store and never returned or logged
 *  (FR-CFG-03, FR-OBS-03). Storing overwrites in place, so re-entering a key corrects it. */
export interface StoreSecretInput {
  readonly reference: string;
  readonly value: string;
}
export interface StoreSecretResult {
  readonly reference: string;
  /** True when the value was written to the store. */
  readonly stored: boolean;
}
export interface SecretStatusInput {
  readonly reference: string;
}
/** Presence only — whether the reference is bound. Never carries the value. */
export interface SecretStatusResult {
  readonly reference: string;
  readonly bound: boolean;
}
export interface DeleteSecretInput {
  readonly reference: string;
}
export interface DeleteSecretResult {
  readonly reference: string;
  /** True when a stored value was removed; false when the reference was already absent. */
  readonly deleted: boolean;
}
/** The result of a Spotify OAuth connect (NIC-133): success + the granted scope only — the tokens
 *  live in the Keychain and never cross the bridge. */
export interface ConnectSpotifyResult {
  readonly connected: boolean;
  readonly scope?: string;
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
  /** Ranked, capability-aware command suggestions over the live catalogs
   *  (NIC-168). Read-only — executing a suggestion still goes through
   *  {@link submitCommand}. */
  suggestCommands(input: SuggestCommandsInput): Promise<SuggestCommandsResult>;
  applyMode(input: ApplyModeInput): Promise<ApplyModeResult>;
  captureNote(input: CaptureNoteInput): Promise<CaptureNoteResult>;
  searchNotes(input: SearchNotesInput): Promise<SearchNotesResult>;
  decideConfirmation(input: DecideConfirmationInput): Promise<DecideConfirmationResult>;
  updateSettings(input: UpdateSettingsInput): Promise<UpdateSettingsResult>;
  /** Read the effective persisted settings so the settings UI initializes its
   *  controls from stored state instead of defaults (NIC-141). */
  getSettings(): Promise<SettingsSnapshot>;

  /** Store an API credential in the Keychain (NIC-134). The value is written, never returned. */
  storeSecret(input: StoreSecretInput): Promise<StoreSecretResult>;
  /** Report whether a logical secret reference is bound, without exposing its value. */
  getSecretStatus(input: SecretStatusInput): Promise<SecretStatusResult>;
  /** Remove a stored secret (NIC-133) — the disconnect / clear-key path. Idempotent. */
  deleteSecret(input: DeleteSecretInput): Promise<DeleteSecretResult>;
  /** Run the Spotify OAuth connect flow on the macOS host (NIC-133): opens the browser, captures
   *  the redirect, and persists tokens to the Keychain. Resolves with the granted scope, or rejects
   *  with an honest message (no Client ID, cancelled, rejected). */
  connectSpotify(): Promise<ConnectSpotifyResult>;
  /** Run the Gmail OAuth connect on the macOS host, or clear the stored grant with
   *  `{disconnect: true}`. Tokens are written to the Keychain and never returned. */
  connectGmail(input?: ConnectGmailInput): Promise<ConnectGmailResult>;
  /** The unread messages themselves, for the email report. On demand only — one request per
   *  message, so this is never sampled on a cadence the way the count is. */
  listUnreadMail(limit?: number): Promise<UnreadMailResult>;
  /** Read-only application discovery for the More Apps picker (NIC-119). */
  listApps(): Promise<ListAppsResult>;
  /** List the user's calendars for the Settings calendar→mode mapping (NIC-126). Requests
   *  Calendar access at point of use; a denied grant returns `authorized: false` + no calendars. */
  listCalendars(): Promise<ListCalendarsResult>;
  /** Create one calendar event from the `create-event` form (quick actions phase 3). */
  createCalendarEvent(input: CreateCalendarEventInput): Promise<CreateCalendarEventResult>;
  /** Clone a repository into the projects root from the `git-clone` form (quick actions phase 4).
   *  Structured rather than a `clone <url>` text submit because the form carries an optional folder
   *  name, which no text grammar carries without becoming lossy about quoting. */
  cloneRepository(input: CloneRepositoryInput): Promise<CloneRepositoryResult>;
  /** Open a native folder picker rooted at the projects root (quick actions phase 4). Takes no
   *  input by design: a caller-supplied starting directory is the first step toward a
   *  caller-chosen destination, which the root constraint exists to prevent. */
  chooseFolder(): Promise<ChooseFolderResult>;
  /** Read the Linear workspace for the `create-ticket` form's dropdowns (quick actions phase 4).
   *  A read that never touches the command bus, like `listCalendars`. */
  listLinearOptions(): Promise<ListLinearOptionsResult>;
  /** One project's standing in the currently-active Linear cycle (NIC-221) — the project detail
   *  window's cycle section. A read that never touches the command bus, like `listLinearOptions`;
   *  `project` is the descriptor's `linear_project`, matched case-insensitively. */
  getLinearProjectCycle(project: string): Promise<GetLinearProjectCycleResult>;
  /** Create one Linear issue from the `create-ticket` form. */
  createLinearIssue(input: CreateLinearIssueInput): Promise<CreateLinearIssueResult>;
  /** Create one Spotify playlist from the `create-playlist` form (quick actions phase 4). Rejects
   *  with `spotify_reconnect_required` when the stored grant predates the playlist scopes. */
  createSpotifyPlaylist(input: CreateSpotifyPlaylistInput): Promise<CreateSpotifyPlaylistResult>;
  /** Create a project folder with a PROJECT.md descriptor (quick actions phase 4). */
  scaffoldProject(input: ScaffoldProjectInput): Promise<ScaffoldProjectResult>;
  /** Read current NFL games and PGA tournaments for `check-scoreboard` (quick actions phase 4).
   *  One call serves both the picker and the report it opens — they read the same document. */
  listSportsEvents(): Promise<ListSportsEventsResult>;
  /** Contacts and existing chats for the `send-text` picker (quick actions phase 4). */
  listMessageRecipients(): Promise<ListMessageRecipientsResult>;
  /** Send one message. Always gates: the result normally reports `awaitingConfirmation`. */
  sendMessage(input: SendMessageInput): Promise<SendMessageResult>;
  /** The Canvas ingest connection state for the Settings connect card (NIC-132) — the pairing
   *  endpoint/token (minted on demand) plus the last scrape's age/counts. */
  getCanvasStatus(): Promise<CanvasStatus>;
  /** Disconnect Canvas (NIC-132): purge the scraped data and rotate the ingest token, returning the
   *  fresh (empty) state. The old token stops working, so the extension must be re-paired. */
  resetCanvas(): Promise<CanvasStatus>;
  /** Hide or unhide a scraped Canvas course/assignment (NIC-132) from the School widgets, returning
   *  the fresh status with each item's hidden flag. Persists across scrapes. */
  setCanvasItemHidden(id: string, hidden: boolean): Promise<CanvasStatus>;
  /** Rebuild the derived note search index from the durable Markdown (NIC-163), for Setup →
   *  Library. Needed after editing notes outside CerebralHelm — the index only learns about those
   *  files when it is rebuilt. Never destructive to the Markdown; rejects if the rebuild fails. */
  rebuildKnowledgeIndex(): Promise<KnowledgeRebuildResult>;
  /** The durable notes under the knowledge root (NIC-162), for the Setup → Library card. `limit`
   *  caps the returned notes (most recently changed first); the reported total is unaffected. */
  listNotes(limit?: number): Promise<ListNotesResult>;
  /** The course notebooks on disk (quick actions phase 5), for `take-notes`' first stage. Reports
   *  only what the vault contains — the live Canvas courses are already in dashboard state, and
   *  the picker merges the two, which is what keeps a finished semester's notes reachable. */
  listCourses(limit?: number): Promise<ListCoursesResult>;
  /** Start a system-health run (quick actions phase 5). Returns as soon as the run STARTS — the
   *  results arrive as `system.checks.changed` events, each carrying the whole set, because the
   *  inventory reaches several third parties and a caller awaiting one response would show
   *  nothing while the interesting part (which checks exist) is already known. */
  runSystemChecks(): Promise<RunSystemChecksResult>;
  /** Create one templated note in a course (quick actions phase 5), minting the course folder on
   *  first use. The caller names a COURSE, never a folder: the host derives the folder inside the
   *  school root, so a note can only ever land there. Never overwrites an existing note. */
  createCourseNote(input: CreateCourseNoteInput): Promise<CreateCourseNoteResult>;
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
