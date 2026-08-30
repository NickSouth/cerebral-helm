import Foundation
import CerebralContracts
import CerebralCore
import CerebralTools

/// The outcome of a successful Spotify connect (NIC-133), returned by the host's connect closure to
/// the `connectSpotify` op: the granted scope only. The OAuth tokens are persisted to the Keychain
/// by the Mac coordinator and never travel back through the bridge.
public struct SpotifyConnectionInfo: Sendable, Equatable {
    public let scope: String?
    public init(scope: String?) {
        self.scope = scope
    }
}

/// The Linear workspace the `create-ticket` form's dropdowns read (quick-actions phase 4).
///
/// Projects and labels are nested **inside** their team, not flattened, because they are scoped to
/// it: a flat list would let the form offer a project belonging to another team, which Linear
/// rejects at write time. `available` is false when the host has no Linear client at all, which is
/// a different fact from "you have no teams".
public struct LinearWorkspaceInfo: Sendable, Equatable {
    public struct Option: Sendable, Equatable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Team: Sendable, Equatable {
        public let id: String
        public let key: String
        public let name: String
        public let projects: [Option]
        public let labels: [Option]

        public init(id: String, key: String, name: String, projects: [Option], labels: [Option]) {
            self.id = id
            self.key = key
            self.name = name
            self.projects = projects
            self.labels = labels
        }
    }

    public let teams: [Team]
    public init(teams: [Team]) {
        self.teams = teams
    }
}

/// One project's standing in the currently-active cycle, as the project detail window needs it
/// (NIC-221). The host-facing shape: `CerebralRuntimeHost` stays free of the Linear client, so the
/// mac adapter maps its own type onto this.
///
/// Timestamps are **ISO-8601 strings, not `Date`** — bridge operation payloads go through a plain
/// `JSONEncoder` (see `encodePayload`), which would render a `Date` as a numeric reference-date
/// offset. Formatting once, explicitly, at the edge that produces them keeps the wire shape from
/// depending on an encoder default.
public struct LinearProjectCycleInfo: Sendable, Equatable {
    public struct State: Sendable, Equatable {
        public let name: String
        /// `backlog` | `unstarted` | `started` | `completed` | `canceled` — the only stable thing
        /// to group on, since a status name is the user's to rename.
        public let type: String
        /// Linear's own colour for the status, so the surface never invents one.
        public let color: String
        public let position: Double

        public init(name: String, type: String, color: String, position: Double) {
            self.name = name
            self.type = type
            self.color = color
            self.position = position
        }
    }

    public struct Issue: Sendable, Equatable {
        public let identifier: String
        public let title: String
        public let url: String
        public let priority: Int
        public let estimate: Int?
        public let sortOrder: Double
        public let state: State
        public let labels: [String]
        /// Linear's handle for the assignee, or `nil` when unassigned.
        public let assignee: String?
        /// Linear's initials for the assignee — what an avatar draws.
        public let assigneeInitials: String?

        public init(
            identifier: String, title: String, url: String, priority: Int, estimate: Int?,
            sortOrder: Double, state: State, labels: [String], assignee: String?,
            assigneeInitials: String?
        ) {
            self.identifier = identifier
            self.title = title
            self.url = url
            self.priority = priority
            self.estimate = estimate
            self.sortOrder = sortOrder
            self.state = state
            self.labels = labels
            self.assignee = assignee
            self.assigneeInitials = assigneeInitials
        }
    }

    public struct Cycle: Sendable, Equatable {
        public let id: String
        public let number: Int
        public let name: String?
        /// ISO-8601, formatted by the producer. See the note on this type.
        public let startsAt: String
        public let endsAt: String

        public init(id: String, number: Int, name: String?, startsAt: String, endsAt: String) {
            self.id = id
            self.number = number
            self.name = name
            self.startsAt = startsAt
            self.endsAt = endsAt
        }
    }

    /// The project's name as Linear spells it, or `nil` when the descriptor's `linear_project`
    /// matches no project — which must not be reported as an empty cycle.
    public let matchedProject: String?
    /// Linear's own URL for the matched project, so the section can offer "open it in Linear"
    /// without composing a URL from a name.
    public let matchedProjectURL: String?
    public let cycle: Cycle?
    public let issues: [Issue]
    public let truncated: Bool

    public init(
        matchedProject: String?,
        matchedProjectURL: String? = nil,
        cycle: Cycle?,
        issues: [Issue],
        truncated: Bool
    ) {
        self.matchedProject = matchedProject
        self.matchedProjectURL = matchedProjectURL
        self.cycle = cycle
        self.issues = issues
        self.truncated = truncated
    }
}


/// A folder the user picked in a native open panel (quick-actions phase 4, `git-clone`).
///
/// `relativePath` is the selection expressed relative to the projects root — the empty string when
/// the root itself was chosen. `outsideRoot` reports a selection the host refused for being outside
/// that root, which is a different fact from cancelling: one deserves an explanation, the other
/// deserves silence. Both are false when nothing was picked at all.
public struct FolderSelectionInfo: Sendable, Equatable {
    public let absolutePath: String?
    public let relativePath: String?
    public let cancelled: Bool
    public let outsideRoot: Bool

    public init(absolutePath: String?, relativePath: String?, cancelled: Bool, outsideRoot: Bool) {
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.cancelled = cancelled
        self.outsideRoot = outsideRoot
    }

    public static let cancelledSelection = FolderSelectionInfo(
        absolutePath: nil, relativePath: nil, cancelled: true, outsideRoot: false
    )
}

/// The Canvas ingest connection state (NIC-132), returned by the host's status/reset closures to the
/// `getCanvasStatus`/`resetCanvas` ops. `endpoint` and `token` are what the user pairs the Chrome
/// extension with; `lastScrapedAt` (ISO-8601, nil when never) and the counts describe the last
/// scrape. The token is a local pairing secret shown once in Settings — never logged.
public struct CanvasStatusInfo: Sendable, Equatable {
    public let endpoint: String
    public let token: String?
    public let lastScrapedAt: String?
    public let courseCount: Int
    public let deadlineCount: Int
    /// Every scraped course/assignment (including hidden ones, flagged), so the settings surface can
    /// list them with a hide/unhide toggle (NIC-132). The counts above are the VISIBLE totals.
    public let courses: [CanvasStatusItem]
    public let deadlines: [CanvasStatusItem]

    public init(
        endpoint: String,
        token: String?,
        lastScrapedAt: String?,
        courseCount: Int,
        deadlineCount: Int,
        courses: [CanvasStatusItem] = [],
        deadlines: [CanvasStatusItem] = []
    ) {
        self.endpoint = endpoint
        self.token = token
        self.lastScrapedAt = lastScrapedAt
        self.courseCount = courseCount
        self.deadlineCount = deadlineCount
        self.courses = courses
        self.deadlines = deadlines
    }
}

/// The outcome of a knowledge-index rebuild (NIC-163), returned by the host's rebuild closure to the
/// `rebuildKnowledgeIndex` op: the knowledge root that was read and how many notes were indexed, so
/// the settings panel reports what the rebuild covered instead of a bare "done". The durable
/// Markdown is never written — only the derived index is reconstructed.
public struct KnowledgeRebuildInfo: Sendable, Equatable {
    public let root: String
    public let noteCount: Int

    public init(root: String, noteCount: Int) {
        self.root = root
        self.noteCount = noteCount
    }
}

/// One scraped Canvas item in the settings manage-list (NIC-132): its id, a display label, and
/// whether the user has hidden it from the School widgets.
public struct CanvasStatusItem: Sendable, Equatable {
    public let id: String
    public let label: String
    public let hidden: Bool

    public init(id: String, label: String, hidden: Bool) {
        self.id = id
        self.label = label
        self.hidden = hidden
    }
}

/// Executes versioned bridge operation requests against the live ``CommandRuntime``
/// (NIC-74b, ADR-004). Transport-agnostic: the WKWebView transport (or a test) hands
/// it a decoded operation request and forwards the response it returns.
///
/// This increment maps the command-style operations — `submitCommand` and
/// `applyMode` — onto `CommandRuntime.submit`. The structured knowledge/confirmation/
/// settings operations, `getBootstrapState`, `getRecentActivity`, and the event
/// stream land in following increments; until then they return a structured
/// `unavailable_capability` error so the dashboard degrades honestly rather than
/// hanging on a missing reply.
public final class BridgeSession: @unchecked Sendable {
    private let runtime: CommandRuntime
    private let configDirectory: URL
    /// Ranks command suggestions (NIC-168) over the runtime's live reference
    /// store, so a reference minted mid-session is suggestible immediately.
    private let suggestionEngine: CommandSuggestionEngine
    /// Parses submitted input pre-bus for the layout-open re-route (unification,
    /// 2026-07-31). Shares the runtime's live reference store, so it always agrees
    /// with the bus parser.
    private let directParser: DirectCommandParser
    /// The full workspace, when the host has one (the shell). Enables the
    /// user-overrides read side (bootstrap composes through `ConfigLoader`, so
    /// pinned quick apps appear — NIC-119c) and the validated override write
    /// path. nil = shipped-defaults composition (tests, workspace-less hosts).
    private let workspace: WorkspacePaths?
    /// Durable settings persistence (FR-CFG-04). Optional so a host without a
    /// database binding (some tests) still validates patches; when absent, an
    /// accepted patch is validated but not saved — the pre-store behavior.
    private let settingsStore: (any SettingsStore)?
    /// The durable active-mode store (FR-MOD-05). When bound, bootstrap restores
    /// the last active mode; when absent, the stored default applies.
    private let modeStateStore: (any ModeStateStore)?
    /// The composed capability flags the handshake reports (FR-SHL-06), derived at
    /// composition time from the bound capability bundle, phase, and platform
    /// permissions (``CompositionCapabilities``). Defaults to the honest pre-Mac
    /// mock set: every native capability unavailable. Mutable because permission
    /// state can change while running (NIC-83) — the shell rechecks on activation
    /// and updates via ``updateCapabilities(_:)``.
    public var capabilities: [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return currentCapabilities
    }

    private let capabilitiesLock = NSLock()
    private var currentCapabilities: [CerebralContracts.Capability]
    private let messageSchemaVersion = "1.0.0"
    /// Emits an already-encoded bridge-event JSON string to the dashboard (Sendable
    /// String — no non-Sendable DTO crosses the transport boundary).
    private let emitEventJSON: @Sendable (String) -> Void

    /// Pending confirmations awaiting a decision, keyed by disclosure id
    /// (== `ConfirmationToken.confirmationID`). The token is a single-use secret held
    /// only here; the dashboard decides by id and never sees the token.
    private let tokenLock = NSLock()
    private var pendingTokens: [String: ConfirmationToken] = [:]

    /// Fetches site favicons for URL quick apps (NIC-147). Optional: a host without
    /// it (tests, workspace-less hosts) simply serves URL tiles without favicons.
    /// The fetch runs in the background off `listUrls`/`addUrlReference`; results are
    /// cached under the state root and pushed live via `mode.quickapps.changed`.
    private let faviconCapability: (any FaviconCapability)?
    /// Origins with an in-flight favicon fetch, so overlapping `listUrls` calls never
    /// crawl the same site twice concurrently.
    private let faviconLock = NSLock()
    private var faviconInFlightOrigins: Set<String> = []

    /// Enumerates the user's Chrome profiles for the profile dropdown and avatar
    /// badges (NIC-151). Optional: a host without it (tests, non-Mac) serves an
    /// empty profile list, so the UI simply offers no profile choices.
    private let chromeProfiles: (any ChromeProfileDiscoveryCapability)?
    /// Lists the user's calendars for the Settings calendar→mode mapping (NIC-126). Optional: a
    /// host without it (tests, non-Mac) serves an unauthorized/empty list, so the UI shows its
    /// honest "grant Calendar access" state.
    private let calendarProvider: (any CalendarProvider)?
    /// Provisions and answers presence for logical secret references (NIC-134): the
    /// `storeSecret`/`getSecretStatus` ops drive it directly, like `secretStore` on the Mac
    /// composition. Optional — a host without it (tests without secrets, pre-Mac) reports the
    /// secret surface honestly unavailable. The stored *value* never leaves this session: it is
    /// written through `store` and its presence read through `resolve`; the response never
    /// echoes it (FR-CFG-03, FR-OBS-03).
    private let secretStore: (any SecretManaging)?
    /// Invoked with the reference after a secret is successfully stored (NIC-134), so a live
    /// consumer — e.g. the releases producer keyed on the TMDB API key — can refresh at once
    /// rather than waiting out its slow cadence. Optional; a host without live secret consumers
    /// leaves it nil.
    private let onSecretStored: (@Sendable (String) -> Void)?

    /// Invoked with the reference after a secret is successfully removed, so a consumer holding
    /// that grant in memory can drop it. Required for correctness, not just freshness: an OAuth
    /// session caches its token to avoid re-reading the Keychain, so without this a Disconnect
    /// would leave the session happily using the credential the user just revoked. Optional; a
    /// host with no such consumer leaves it nil.
    private let onSecretDeleted: (@Sendable (String) -> Void)?

    /// Invoked after a settings patch is durably applied, carrying the applied changes, so a
    /// host can refresh a live producer that depends on a setting (e.g. the Stocks producer
    /// re-samples when the ticker list changes, NIC-128) instead of waiting out its slow
    /// cadence. Optional; a host with no settings-driven producers leaves it nil.
    private let onSettingsChanged: (@Sendable (SettingsChanges) -> Void)?

    /// Invoked with the entered mode id after a successful mode switch (either the `applyMode`
    /// operation or a raw `mode <id>` command), so a host can refresh the entered mode's live
    /// widget producers at once — the dashboard shows fresh data on entry instead of each
    /// producer's last cadence tick. Optional; a host without live producers leaves it nil.
    private let onModeApplied: (@Sendable (String) -> Void)?

    /// Runs the Spotify OAuth connect flow (NIC-133): the `connectSpotify` op awaits it, and it
    /// resolves once the browser round trip completes (tokens are persisted to the Keychain by the
    /// coordinator) or throws honestly (no Client ID, user cancelled, Spotify rejected). Optional —
    /// a host without the Mac coordinator (pre-Mac, tests) reports the connect surface unavailable.
    /// The tokens never cross back through here; only the granted scope does.
    private let spotifyConnect: (@Sendable () async throws -> SpotifyConnectionInfo)?

    /// Reads the Canvas ingest connection state for `getCanvasStatus` (NIC-132) — the pairing
    /// endpoint/token plus the last-scrape summary. Optional: a host without the Mac ingest store
    /// reports the surface unavailable. `canvasReset` purges the scraped data and rotates the token
    /// (the disconnect path), returning the fresh state.
    /// Opens a native folder picker rooted at the projects root and returns what the user chose
    /// (quick-actions phase 4). Optional: a host with no window server — pre-Mac, tests, the
    /// browser preview — reports the picker unavailable rather than pretending to open one. The
    /// **root constraint is enforced host-side**, not by the caller, so a selection outside it
    /// comes back refused rather than as a path the tool would then have to reject.
    private let chooseFolder: (@Sendable () async -> FolderSelectionInfo)?

    /// Reads the Linear workspace for `listLinearOptions` (quick-actions phase 4) — the teams,
    /// projects and labels the `create-ticket` dropdowns offer. Optional: a host without the Linear
    /// client reports the surface unavailable. Deliberately a **read** closure, separate from the
    /// `linear.createissue` tool that writes, so listing options can never reach the write path.
    private let linearWorkspace: (@Sendable () async throws -> LinearWorkspaceInfo)?

    /// Reads one project's active-cycle standing for `getLinearProjectCycle` (NIC-221) — the
    /// project detail window's cycle section. Optional: a host without the Linear client reports
    /// the surface unavailable. A **third** read closure, separate from both `linearWorkspace` and
    /// the `linear.createissue` tool, so a surface that renders a project's status can never reach
    /// the one that files tickets.
    private let linearProjectCycle: (@Sendable (String) async throws -> LinearProjectCycleInfo)?

    /// Reads current sports events for `listSportsEvents` (quick-actions phase 4) — the
    /// `check-scoreboard` picker and the report it opens. Optional: a host without the provider
    /// reports the surface unavailable. A read, never the command bus: the user is choosing games
    /// and reading scores, not acting on the world.
    private let sportsEvents: (@Sendable () async throws -> [SportsEvent])?

    /// Lists who a message can go to for `listMessageRecipients` (quick-actions phase 4). A read
    /// closure, deliberately separate from the `messages.send` tool: a surface that lists people
    /// must not be able to reach the one that sends to them.
    private let messageRecipients: (@Sendable () async throws -> [MessageRecipient])?

    private let canvasStatus: (@Sendable () async -> CanvasStatusInfo)?
    private let canvasReset: (@Sendable () async -> CanvasStatusInfo)?
    /// Hides or unhides a scraped Canvas item by id (NIC-132), returning the fresh status. Optional —
    /// a host without the ingest store reports the surface unavailable.
    private let canvasSetHidden: (@Sendable (String, Bool) async -> CanvasStatusInfo)?

    /// Rebuilds the derived note search index from the durable Markdown for
    /// `rebuildKnowledgeIndex` (NIC-163), returning the knowledge root it read and
    /// how many notes it indexed. Deliberately **not** a bus tool: it maintains
    /// derived state rather than acting on the user's behalf, like `resetCanvas`.
    /// It never writes to the Markdown — a rebuild can lose nothing, because the
    /// files are the source of truth. Optional: a host without a workspace reports
    /// the surface honestly unavailable rather than claiming a rebuild happened.
    private let knowledgeRebuild: (@Sendable () async throws -> KnowledgeRebuildInfo)?
    /// Composes one Report with a model (NIC-228), or nil on a host with no model configured.
    ///
    /// Injected as a closure rather than assembled here for the usual reason: the composer needs a
    /// concrete `ModelProvider`, an Assembler wired to platform providers, and the profile catalog,
    /// none of which this AppKit-free file can build. What it does own is the marshalling — and the
    /// rule that a host without one answers honestly rather than pretending.
    private let composeReport: (@Sendable (String, @escaping @Sendable ([Block]) -> Void) async -> ReportCompositionOutcome)?
    /// The health checks this host can run (quick actions phase 5). Injected rather than built
    /// here: the inventory is platform-specific (macOS permissions, installed apps) and this file
    /// stays AppKit-free. A host with none simply has no checks to run and says so.
    private let systemChecks: (@Sendable () -> [any HealthCheck])?
    /// Runs the Gmail OAuth connect on the macOS host. Returns the granted scope and whether the
    /// grant can renew itself; the tokens never cross back to the UI.
    private let gmailConnect: (@Sendable () async throws -> GmailConnectionInfo)?
    /// Removes the stored Gmail grant (local only — it does not revoke at Google).
    private let gmailDisconnect: (@Sendable () async throws -> Void)?
    /// Lists unread mail on demand for the email report. **Never sampled** — one request per
    /// message, so it runs when the report opens and not on any cadence.
    private let unreadMail: (@Sendable (Int) async throws -> [MailMessage])?
    /// Guards the single-run slot. A plain lock rather than an actor because the whole critical
    /// section is two field accesses, and the surrounding session is not isolated.
    private let systemCheckLock = NSLock()
    private var systemCheckRunning = false
    /// Which reports have a composition in flight (NIC-253). Keyed by report id rather than a single
    /// flag: the daily brief and a future email report are independent work, and one must not lock
    /// the other out.
    private let compositionLock = NSLock()
    private var composingReports: Set<String> = []

    /// Hides a layout's app windows on `closeLayout` (NIC-142) — the same
    /// permission-free `NSRunningApplication` primitive "Windows Stored by Mode"
    /// uses. Optional: a host without it (pre-Mac, tests) still ends the session
    /// and clears the bar, but cannot hide the windows (honestly degraded).
    private let workspaceWindows: (any WorkspaceWindowsCapability)?

    /// Surfaces a layout quick-toggle target on `toggleLayout` (NIC-142): the same
    /// app/URL open capabilities the runtime uses, called directly. The layout
    /// session is authorized once at open, so a rapid toggle does not re-confirm
    /// (owner decision) — these bypass the confirmation gate the way `closeLayout`'s
    /// hide does, never a per-press prompt. The shared URL capability reuses the
    /// runtime's tab-surfacing registry, so toggling to a URL surfaces its tab.
    private let app: (any AppCapability)?
    private let url: (any URLCapability)?

    /// Reads visible windows' frames for live layout capture (NIC-142) — the AX
    /// geometry capability. Optional: absent pre-Mac, so capture degrades honestly.
    private let window: (any WindowCapability)?

    /// Enumerates and acts on individual open windows for the window navigator
    /// (NIC-143): list, minimize, surface, close. Direct-capability like the layout
    /// ops — navigator actions are authorized as benign local view changes, never a
    /// per-press confirmation. Optional: absent pre-Mac/tests, so the navigator
    /// degrades to an honest empty inventory and no-op actions. The live AX adapter
    /// lands in a later increment.
    private let appWindows: (any AppWindowsCapability)?
    /// Resolves the default browser's bundle id (NIC-142) so a layout URL window that
    /// opens in the default browser (no Chrome profile) can be arranged like an app.
    /// A URL with a Chrome profile always targets `com.google.Chrome`.
    private let defaultBrowserBundleID: (@Sendable () -> String?)?

    /// The active layout session (NIC-142), when a layout is open. Ephemeral
    /// runtime state — started by `openLayout`, cleared by `closeLayout` or a mode
    /// switch. Guarded by its own lock; the session is the only source of the
    /// `layout.session.changed` state.
    private let layoutLock = NSLock()
    private var activeLayoutSession: LayoutSession?

    /// The session-only, per-mode collapse-all buckets (NIC-143). In-memory and not
    /// persisted — a relaunch starts every mode expanded. Owned wholly by the bridge:
    /// the toggle op fills/empties it, and a mode switch re-applies the entered mode's
    /// bucket after any "Windows Stored by Mode" restore (the bucket wins).
    private let collapseStore = ModeCollapseStore()

    public init(
        runtime: CommandRuntime,
        configDirectory: URL,
        workspace: WorkspacePaths? = nil,
        capabilities: [CerebralContracts.Capability] = CompositionCapabilities.bridgeCapabilities(phase: .preMac, nativeCapabilityIDs: []),
        settingsStore: (any SettingsStore)? = nil,
        modeStateStore: (any ModeStateStore)? = nil,
        faviconCapability: (any FaviconCapability)? = nil,
        chromeProfiles: (any ChromeProfileDiscoveryCapability)? = nil,
        calendarProvider: (any CalendarProvider)? = nil,
        secretStore: (any SecretManaging)? = nil,
        onSecretStored: (@Sendable (String) -> Void)? = nil,
        onSecretDeleted: (@Sendable (String) -> Void)? = nil,
        onSettingsChanged: (@Sendable (SettingsChanges) -> Void)? = nil,
        onModeApplied: (@Sendable (String) -> Void)? = nil,
        spotifyConnect: (@Sendable () async throws -> SpotifyConnectionInfo)? = nil,
        chooseFolder: (@Sendable () async -> FolderSelectionInfo)? = nil,
        linearWorkspace: (@Sendable () async throws -> LinearWorkspaceInfo)? = nil,
        linearProjectCycle: (@Sendable (String) async throws -> LinearProjectCycleInfo)? = nil,
        sportsEvents: (@Sendable () async throws -> [SportsEvent])? = nil,
        messageRecipients: (@Sendable () async throws -> [MessageRecipient])? = nil,
        canvasStatus: (@Sendable () async -> CanvasStatusInfo)? = nil,
        canvasReset: (@Sendable () async -> CanvasStatusInfo)? = nil,
        canvasSetHidden: (@Sendable (String, Bool) async -> CanvasStatusInfo)? = nil,
        knowledgeRebuild: (@Sendable () async throws -> KnowledgeRebuildInfo)? = nil,
        systemChecks: (@Sendable () -> [any HealthCheck])? = nil,
        composeReport: (@Sendable (String, @escaping @Sendable ([Block]) -> Void) async -> ReportCompositionOutcome)? = nil,
        gmailConnect: (@Sendable () async throws -> GmailConnectionInfo)? = nil,
        gmailDisconnect: (@Sendable () async throws -> Void)? = nil,
        unreadMail: (@Sendable (Int) async throws -> [MailMessage])? = nil,
        workspaceWindows: (any WorkspaceWindowsCapability)? = nil,
        app: (any AppCapability)? = nil,
        url: (any URLCapability)? = nil,
        window: (any WindowCapability)? = nil,
        appWindows: (any AppWindowsCapability)? = nil,
        defaultBrowserBundleID: (@Sendable () -> String?)? = nil,
        emitEventJSON: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.configDirectory = configDirectory
        self.workspace = workspace
        self.settingsStore = settingsStore
        self.modeStateStore = modeStateStore
        self.faviconCapability = faviconCapability
        self.chromeProfiles = chromeProfiles
        self.calendarProvider = calendarProvider
        self.secretStore = secretStore
        self.onSecretStored = onSecretStored
        self.onSecretDeleted = onSecretDeleted
        self.onSettingsChanged = onSettingsChanged
        self.onModeApplied = onModeApplied
        self.spotifyConnect = spotifyConnect
        self.chooseFolder = chooseFolder
        self.linearWorkspace = linearWorkspace
        self.linearProjectCycle = linearProjectCycle
        self.sportsEvents = sportsEvents
        self.messageRecipients = messageRecipients
        self.canvasStatus = canvasStatus
        self.canvasReset = canvasReset
        self.canvasSetHidden = canvasSetHidden
        self.knowledgeRebuild = knowledgeRebuild
        self.systemChecks = systemChecks
        self.composeReport = composeReport
        self.gmailConnect = gmailConnect
        self.gmailDisconnect = gmailDisconnect
        self.unreadMail = unreadMail
        self.workspaceWindows = workspaceWindows
        self.app = app
        self.url = url
        self.window = window
        self.appWindows = appWindows
        self.defaultBrowserBundleID = defaultBrowserBundleID
        self.currentCapabilities = capabilities
        self.emitEventJSON = emitEventJSON
        // Suggestion ranking (NIC-168) shares the parser's live reference store and
        // adds display labels for the id-only catalogs (modes, workflows). Label
        // loading degrades to bare ids — never blocks the session.
        var modeLabels: [String: String] = [:]
        if case let .valid(config) = ConfigValidator.validate(configDirectory: configDirectory) {
            modeLabels = Dictionary(config.modes.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        }
        let workflowLabels = ((try? WorkflowCatalogLoader.load(configDirectory: configDirectory)) ?? [:])
            .mapValues(\.label)
        self.suggestionEngine = CommandSuggestionEngine(
            referenceStore: runtime.referenceCatalog,
            modeLabels: modeLabels,
            workflowLabels: workflowLabels
        )
        self.directParser = DirectCommandParser(referenceStore: runtime.referenceCatalog)
    }

    /// The one composition every snapshot/bootstrap emission uses: through the
    /// layered loader (user overrides included) when a workspace is bound, else
    /// the shipped defaults.
    private func composeState(activeModeID: String?) -> CerebralHelmBridgeBootstrapState {
        // When the live-metrics provider is available a sample is inbound, so the composed
        // System Health region loads (`.empty`) rather than reporting unavailable — the shell
        // shows a same-shape skeleton instead of an "unavailable" flash on first paint or a
        // mode switch (NIC-136). Absent the provider it stays honestly unavailable.
        let metricsExpected = capabilities.first { $0.id == "system.metrics" }?.available == true
        if let workspace {
            return BootstrapComposer.compose(
                workspace: workspace, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
            )
        }
        return BootstrapComposer.compose(
            configDirectory: configDirectory, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
        )
    }

    /// Replaces the reported capability set (a permission recheck, NIC-83) and
    /// returns the capabilities whose availability changed, so the caller can
    /// emit one `bridge.capability.changed` event per transition. Future
    /// handshakes report the updated set.
    public func updateCapabilities(
        _ updated: [CerebralContracts.Capability]
    ) -> [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        let previousByID = Dictionary(uniqueKeysWithValues: currentCapabilities.map { ($0.id, $0) })
        currentCapabilities = updated
        return updated.filter { capability in
            previousByID[capability.id]?.available != capability.available
        }
    }

    public func execute(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        switch request.operation {
        case .getBootstrapState:
            return ok(request, payload: composeBootstrapState())
        case .submitCommand:
            return await submitCommand(request)
        case .suggestCommands:
            return await suggestCommands(request)
        case .applyMode:
            return await applyMode(request)
        case .captureNote:
            return await captureNote(request)
        case .searchNotes:
            return await searchNotes(request)
        case .getRecentActivity:
            return getRecentActivity(request)
        case .decideConfirmation:
            return await decideConfirmation(request)
        case .updateSettings:
            return updateSettings(request)
        case .listApps:
            return await listApps(request)
        case .updateQuickApps:
            return updateQuickApps(request)
        case .addURLReference:
            return addUrlReference(request)
        case .listUrls:
            return listUrls(request)
        case .listChromeProfiles:
            return await listChromeProfiles(request)
        case .addChromeProfileReference:
            return addChromeProfileReference(request)
        case .runSpeedTest:
            return await runSpeedTest(request)
        case .getSettings:
            return getSettings(request)
        case .storeSecret:
            return await storeSecret(request)
        case .getSecretStatus:
            return await getSecretStatus(request)
        case .deleteSecret:
            return await deleteSecret(request)
        case .connectSpotify:
            return await connectSpotify(request)
        case .openLayout:
            return await openLayout(request)
        case .closeLayout:
            return await closeLayout(request)
        case .toggleLayout:
            return await toggleLayout(request)
        case .pinLayoutWindow:
            return await pinLayoutWindow(request)
        case .updateLayout:
            return await updateLayout(request)
        case .captureLayout:
            return await captureLayout(request)
        case .addLayoutTarget:
            return await addLayoutTarget(request)
        case .toggleModeCollapse:
            return await toggleModeCollapse(request)
        case .closeAllWindows:
            return await closeAllWindows(request)
        case .listWindows:
            return await listWindows(request)
        case .listCalendars:
            return await listCalendars(request)
        case .createCalendarEvent:
            return await createCalendarEvent(request)
        case .cloneRepository:
            return await cloneRepository(request)
        case .chooseFolder:
            return await chooseFolderOperation(request)
        case .listLinearOptions:
            return await listLinearOptions(request)
        case .getLinearProjectCycle:
            return await getLinearProjectCycle(request)
        case .listSportsEvents:
            return await listSportsEvents(request)
        case .listMessageRecipients:
            return await listMessageRecipients(request)
        case .sendMessage:
            return await sendMessage(request)
        case .createLinearIssue:
            return await createLinearIssue(request)
        case .createSpotifyPlaylist:
            return await createSpotifyPlaylist(request)
        case .scaffoldProject:
            return await scaffoldProject(request)
        case .getCanvasStatus:
            return await getCanvasStatus(request)
        case .resetCanvas:
            return await resetCanvas(request)
        case .setCanvasItemHidden:
            return await setCanvasItemHidden(request)
        case .rebuildKnowledgeIndex:
            return await rebuildKnowledgeIndex(request)
        case .listNotes:
            return await listNotes(request)
        case .listCourses:
            return await listCourses(request)
        case .createCourseNote:
            return await createCourseNote(request)
        case .runSystemChecks:
            return await runSystemChecks(request)
        case .composeReport:
            return await composeReport(request)
        case .connectGmail:
            return await connectGmail(request)
        case .listUnreadMail:
            return await listUnreadMail(request)
        case .minimizeWindow:
            return await windowAction(request) { try await $0.minimize(windowID: $1) }
        case .surfaceWindow:
            return await windowAction(request) { try await $0.surface(windowID: $1) }
        case .closeWindow:
            return await windowAction(request) { try await $0.close(windowID: $1) }
        default:
            // captureNote (confirmation-gated local_write returning a synchronous
            // noteId) and subscribe follow later.
            return unimplemented(request)
        }
    }

    // MARK: - Operations

    private func submitCommand(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SubmitCommandInput = decodePayload(request), !input.rawInput.isEmpty else {
            return invalidInput(request, "submitCommand requires a non-empty rawInput.")
        }
        // Honor an explicit, known source; default to `dashboard`. This keeps the
        // command bus honest about provenance (FR-CMD-01) without trusting arbitrary
        // strings.
        // Layout-open unification (owner decision, 2026-07-31): a submitted
        // `run open-<mode>-layout` enters the SAME layout session the bottom bar
        // opens — override-merged frames, hotswap prep, quick-toggle in the bar —
        // instead of replaying the shipped-config workflow through the bus. One
        // behavior for every entry point (typed command, suggestion, quick-action
        // tile, bottom bar). A mode without an authored layout keeps running its
        // static workflow through the bus unchanged.
        if case let .parsed(.runAction(actionID)) = directParser.parse(input.rawInput),
           let modeID = layoutModeID(forWorkflowID: actionID),
           await enterLayoutSession(modeID: modeID) {
            recordRecentCommand(input.rawInput)
            // The session entry is the executor-bypass path authorized at open
            // (NIC-142 owner direction) — no bus command exists, so the receipt
            // carries no command id.
            return ok(request, payload: CommandReceipt(commandId: "", accepted: true))
        }
        let source = input.source.flatMap(CommandSource.init(rawValue:)) ?? .dashboard
        let outcome = await runtime.submit(input.rawInput, source: source)
        registerAwaitingConfirmation(outcome)
        await emitConfigChangedIfModeApplied(outcome)
        let commandReceipt = receipt(for: outcome)
        if commandReceipt.accepted {
            recordRecentCommand(input.rawInput)
        }
        return ok(request, payload: commandReceipt)
    }

    // MARK: - Recent direct commands (NIC-168 / PRD §9.4)

    /// A bounded, session-local ring of accepted raw inputs, newest first — the
    /// source for empty-query "recent direct commands" suggestions. Deliberately
    /// in-memory only: durable command history persists REDACTED input (nil today,
    /// FR-CMD-06), so re-runnable raw strings never touch storage. A fresh launch
    /// starts empty and the surface degrades to the grammar listing.
    private static let recentCommandsCap = 20
    private let recentCommandsLock = NSLock()
    private var recentRawInputs: [String] = []

    private func recordRecentCommand(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentCommandsLock.lock()
        defer { recentCommandsLock.unlock() }
        recentRawInputs.removeAll { $0 == trimmed }
        recentRawInputs.insert(trimmed, at: 0)
        if recentRawInputs.count > Self.recentCommandsCap {
            recentRawInputs.removeLast(recentRawInputs.count - Self.recentCommandsCap)
        }
    }

    private func snapshotRecentCommands() -> [String] {
        recentCommandsLock.lock()
        defer { recentCommandsLock.unlock() }
        return recentRawInputs
    }

    /// Ranked, capability-aware command suggestions for the palette and launcher
    /// (NIC-168). Read-only: ranking never executes anything — execution still
    /// flows through `submitCommand`, the bus, and the policy engine. Availability
    /// is stamped from the live capability set so a suggestion is never shown
    /// runnable when the bridge cannot perform it (FR-UI-07). An empty query is
    /// valid and lists the supported grammar.
    private func suggestCommands(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SuggestCommandsInput = decodePayload(request) else {
            return invalidInput(request, "suggestCommands requires a query string.")
        }
        // Installed-app completeness (NIC-168): a throttled discovery mints every
        // installed app into the reference catalog, so any app is matchable by
        // name — at most one scan per TTL, and only where discovery is available.
        await refreshAppCatalogForSuggestionsIfDue()
        let limit = min(max(input.limit ?? CommandSuggestionEngine.defaultLimit, 1), 25)
        var ranked = suggestionEngine.suggest(input.query, limit: limit)
        if input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // PRD §9.4: an empty query leads with recent direct commands (this
            // session's accepted, still-resolvable ones), then the grammar.
            let recents = suggestionEngine.recentSuggestions(snapshotRecentCommands())
            let recentCommands = Set(recents.map(\.command))
            ranked = Array((recents + ranked.filter { !recentCommands.contains($0.command) }).prefix(limit))
        }
        let capabilityByID = Dictionary(
            capabilities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let suggestions = ranked.map { suggestion in
            let requirement = Self.requiredCapability(for: suggestion.kind)
            let capability = requirement.flatMap { capabilityByID[$0] }
            let available = requirement == nil || capability?.available == true
            return CommandSuggestionDTO(
                command: suggestion.command,
                label: suggestion.label,
                detail: suggestion.detail,
                kind: suggestion.kind.rawValue,
                requiresArgument: suggestion.requiresArgument,
                available: available,
                unavailableReason: available
                    ? nil
                    : (capability?.degradedReason ?? "Not available on this host yet.")
            )
        }
        return ok(request, payload: SuggestCommandsResult(suggestions: suggestions))
    }

    /// The capability a suggestion kind depends on to actually execute; nil means
    /// the kind runs everywhere the bus does (modes, notes, workflows degrade
    /// step-by-step at execution rather than being hidden here).
    private static func requiredCapability(for kind: CommandSuggestion.Kind) -> String? {
        switch kind {
        case .app: return "native.app.open"
        case .url: return "native.url.open"
        case .hook: return "native.hook.run"
        case .workflow, .mode, .command, .pattern: return nil
        }
    }

    /// A raw `mode <id>` command (palette, CLI-over-bridge) that succeeded also
    /// re-themes the dashboard, exactly like the `applyMode` operation — one
    /// switch, one visible result, regardless of which surface asked.
    private func emitConfigChangedIfModeApplied(_ outcome: CommandRuntimeOutcome) async {
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let result, result.toolID == "mode.apply",
            let output = result.output,
            let decoded = try? CerebralHelmModeApplyOutput(data: output)
        else { return }
        // A mode switch ends any active layout session — the outgoing layout's
        // windows fall under the mode's own snapshot behavior (NIC-142).
        endActiveLayoutSession()
        let snapshot = composeState(activeModeID: decoded.modeID)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        await reapplyCollapseBucket(enteredModeID: decoded.modeID)
        // The entered mode's live widget producers refresh at once, so its widgets show
        // fresh data on entry rather than their last cadence tick.
        onModeApplied?(decoded.modeID)
    }

    private func applyMode(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ApplyModeInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "applyMode requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "error"))
        }
        // A mode switch is a real command: `mode.apply` persists the active mode
        // and records a session (FR-MOD-05/06). It runs no workflow steps — the
        // dashboard swap below and the durable switch are the whole effect
        // (workspace re-scope, NIC-85).
        _ = await runtime.submit("mode \(input.modeId)", source: .dashboard)
        // A mode switch ends any active layout session (NIC-142).
        endActiveLayoutSession()
        // Re-theme the dashboard by emitting the target mode's snapshot.
        let snapshot = composeState(activeModeID: input.modeId)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        await reapplyCollapseBucket(enteredModeID: input.modeId)
        // The entered mode's live widget producers refresh at once, so its widgets show
        // fresh data on entry rather than their last cadence tick.
        onModeApplied?(input.modeId)
        return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "ok"))
    }

    // MARK: - Collapse / expand all (NIC-143)

    /// Toggles the collapse-all state of a mode: on collapse, captures the currently
    /// visible applications and hides them into the mode's session-only bucket; on
    /// expand, un-hides exactly that bucket and clears it. Uses the same permission-free
    /// app-level hide/unhide as "Windows Stored by Mode" (owner decision: hide, not
    /// Dock-minimize) and never re-confirms — it is a benign local view change. Collapsing
    /// an empty desktop is a no-op (nothing to hide, so the mode stays expanded). Emits
    /// `mode.windowcollapse.changed` so the bottom-bar icon reflects the new state.
    private func toggleModeCollapse(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ToggleModeCollapseInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "toggleModeCollapse requires a modeId.")
        }
        // Without the app-level window capability (pre-Mac, tests) we cannot hide or
        // return windows, so the collapse state cannot change — report it honestly.
        guard let windows = workspaceWindows else {
            return ok(request, payload: ToggleModeCollapseResult(
                collapsed: collapseStore.isCollapsed(modeID: input.modeId)
            ))
        }

        let collapsed: Bool
        if collapseStore.isCollapsed(modeID: input.modeId) {
            // Expand: un-hide only the apps this mode collapsed (windows opened since
            // are left as-is), then clear the bucket.
            let bucket = collapseStore.expand(modeID: input.modeId)
            if !bucket.isEmpty {
                _ = try? await windows.unhideApplications(bundleIDs: bucket)
            }
            collapsed = false
        } else {
            // Collapse: capture the currently visible apps (the capability already
            // excludes the host app) and hide them. Nothing visible ⇒ no-op.
            let visible = (try? await windows.visibleApplicationBundleIDs()) ?? []
            guard !visible.isEmpty else {
                return ok(request, payload: ToggleModeCollapseResult(collapsed: false))
            }
            _ = try? await windows.hideApplications(bundleIDs: visible)
            collapseStore.collapse(modeID: input.modeId, bundleIDs: visible)
            collapsed = true
        }
        emit(BridgeEventFactory.windowCollapseChangedEvent(
            modeId: input.modeId, collapsed: collapsed,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ToggleModeCollapseResult(collapsed: collapsed))
    }

    /// Close all windows across every mode (NIC-143): quits every open regular
    /// application (except CerebralHelm). Routes through the command bus like any
    /// destructive tool — `apps.quitall` is `destructive`, so the policy engine gates
    /// it on a confirmation. This mirrors `submitCommand`: register the awaiting
    /// confirmation (pushing the disclosure) and return an accepting receipt; the quit
    /// happens only after the user approves through the normal confirmation flow.
    private func closeAllWindows(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let outcome = await runtime.submit("quit-all", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        return ok(request, payload: receipt(for: outcome))
    }

    // MARK: - Window navigator (NIC-143)

    /// The window-navigator inventory: every open window grouped by application. A
    /// direct-capability read, no confirmation. Degrades to an honest empty list when
    /// the capability is absent (pre-Mac / before the live AX adapter lands).
    private func listWindows(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let groups = (try? await appWindows?.listWindows()) ?? []
        let apps = groups.map { group in
            WindowGroupDTO(
                bundleId: group.bundleID,
                appName: group.appName,
                appIconPng: group.appIconPNGBase64,
                windows: group.windows.map { WindowDTO(id: $0.id, title: $0.title, minimized: $0.minimized) }
            )
        }
        return ok(request, payload: WindowInventory(apps: apps))
    }

    /// Shared body for the minimize/surface/close window actions (NIC-143): resolve the
    /// window id and run the action, reporting whether it took effect. A benign local
    /// view change (surface/minimize) or the equivalent of the window's own close button
    /// — direct-capability, no per-press confirmation. No-op `ok: false` when the
    /// capability is absent or the id is unknown.
    private func windowAction(
        _ request: CerebralHelmBridgeOperationRequest,
        _ act: @escaping (any AppWindowsCapability, String) async throws -> Bool
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: WindowRefInput = decodePayload(request), !input.windowId.isEmpty else {
            return invalidInput(request, "a window action requires a windowId.")
        }
        guard let capability = appWindows else {
            return ok(request, payload: WindowActionResult(ok: false))
        }
        let affected = (try? await act(capability, input.windowId)) ?? false
        return ok(request, payload: WindowActionResult(ok: affected))
    }

    /// After a mode switch, re-apply the entered mode's collapse bucket (NIC-143):
    /// "Windows Stored by Mode" restore-on-enter may have un-hidden apps the user had
    /// collapsed, so re-hide anything still in that mode's bucket — the collapse bucket
    /// is authoritative for its mode (owner: "a window state by mode, like open/closed").
    /// Always (re)announces the entered mode's collapse state so the bottom-bar icon is
    /// correct for the mode now shown, even when nothing needed re-hiding.
    private func reapplyCollapseBucket(enteredModeID: String) async {
        let collapsed = collapseStore.isCollapsed(modeID: enteredModeID)
        if collapsed,
           let bucket = collapseStore.bucket(modeID: enteredModeID), !bucket.isEmpty,
           let windows = workspaceWindows {
            _ = try? await windows.hideApplications(bundleIDs: bucket)
        }
        emit(BridgeEventFactory.windowCollapseChangedEvent(
            modeId: enteredModeID, collapsed: collapsed,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    // MARK: - Layout session (NIC-142)

    /// Enters layout mode for a mode: starts the bottom-bar layout session from the
    /// mode's authored layout (emitting `layout.session.changed`) and opens its
    /// windows by running the synthesized `open-<mode>-layout` workflow through the
    /// command bus — a normal, aggregate-confirmed sequence of narrow tool steps.
    ///
    /// The session is populated from the *authored config*, not the workflow result:
    /// the workflow is confirmation-gated (`local_write`), so it may still be
    /// awaiting the user's approval when this returns. The bar reflects the layout's
    /// intent immediately; the windows open once approved.
    private func openLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: OpenLayoutInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "openLayout requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: OpenLayoutResult(accepted: false, modeId: input.modeId))
        }
        guard await enterLayoutSession(modeID: input.modeId) else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "no_layout",
                message: "Mode \"\(input.modeId)\" has no authored layout."
            )
        }
        return ok(request, payload: OpenLayoutResult(accepted: true, modeId: input.modeId))
    }

    /// Enters layout mode for a mode with an authored layout: builds the session,
    /// emits `layout.session.changed` (the bottom bar grows its quick-toggle), and
    /// opens + arranges the whole layout. The single implementation behind BOTH the
    /// `openLayout` operation and a submitted `run open-<mode>-layout` command
    /// (unification, owner decision 2026-07-31) — every entry point produces the
    /// identical layout-mode experience. Returns false when the mode has no
    /// resolvable layout.
    ///
    /// Force the correct setup on open (NIC-142, owner direction 2026-07-15): open and
    /// arrange EVERY static window + hotswap target from the authored (override-merged)
    /// layout so nothing cold-starts on toggle, then hide the inactive hotswaps.
    /// Direct capability calls (authorized once at open; the same executor bypass as
    /// toggle/close). This supersedes the synthesized-workflow open, which read the
    /// SHIPPED layout and so fought the override-merged session's frames.
    private func enterLayoutSession(modeID: String) async -> Bool {
        guard let layout = resolveLayout(modeID: modeID) else { return false }
        let session = buildLayoutSession(modeID: modeID, layout: layout)
        setActiveLayoutSession(session)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: session.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        await openAndArrangeLayout(layout: layout, session: session)
        return true
    }

    /// The mode whose authored layout a synthesized `open-<mode>-layout` workflow id
    /// names, or nil when the id is not a layout opener — or the mode has no authored
    /// layout, in which case its static workflow (if any) stays a plain bus workflow.
    private func layoutModeID(forWorkflowID id: String) -> String? {
        guard id.hasPrefix("open-"), id.hasSuffix("-layout") else { return nil }
        let modeID = String(id.dropFirst("open-".count).dropLast("-layout".count))
        guard !modeID.isEmpty,
              BootstrapComposer.modeExists(modeID, configDirectory: configDirectory),
              resolveLayout(modeID: modeID) != nil
        else { return nil }
        return modeID
    }

    /// Opens + arranges an entire layout on entry (NIC-142): every static window and
    /// EVERY hotswap target is opened and arranged into its frame from the resolved
    /// (override-merged) layout, then the inactive hotswap apps are hidden so only the
    /// active one shows. Opening all hotswaps up front means toggling never cold-starts
    /// a window (owner direction). URL windows are opened but not arranged (a URL is not
    /// an app; browser placement is a later increment). App-level hide, so two hotswaps
    /// sharing a bundle (e.g. two Chrome profiles) are never hidden out from under the
    /// active one.
    private func openAndArrangeLayout(layout: Layout, session: LayoutSession) async {
        // ref → bundle id for app windows, from the already-resolved session.
        var appBundleByRef: [String: String] = [:]
        for window in session.windows where window.bundleID != nil {
            appBundleByRef[window.ref] = window.bundleID
        }
        for target in session.quickToggle?.targets ?? [] where target.bundleID != nil {
            appBundleByRef[target.ref] = target.bundleID
        }
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )

        // The window to arrange for a ref: the app bundle for an app, or the browser
        // bundle for a URL (Chrome for a profiled URL, else the default browser) — a
        // URL "window" is its browser (NIC-142).
        func arrangeBundle(_ ref: String, kind: Kind) -> String? {
            switch kind {
            case .app:
                return appBundleByRef[ref]
            case .url:
                guard let entry = references?.urls[ref] else { return nil }
                return entry.profile != nil ? UserChromeProfileReferences.chromeBundleID : defaultBrowserBundleID?()
            }
        }
        func arrange(_ ref: String, kind: Kind, _ frameRaw: String) async {
            guard let bundle = arrangeBundle(ref, kind: kind), let frame = WindowFrame(rawValue: frameRaw) else {
                return
            }
            _ = try? await window?.arrange(bundleID: bundle, frame: frame, display: .primary)
        }
        func surface(_ ref: String, kind: Kind) async {
            switch kind {
            case .app: _ = try? await app?.open(appID: ref)
            case .url: _ = try? await url?.open(urlID: ref)
            }
        }

        // Static windows: open + arrange (apps and URLs).
        for staticWindow in layout.windows {
            await surface(staticWindow.ref, kind: staticWindow.kind)
            await arrange(staticWindow.ref, kind: staticWindow.kind, staticWindow.frame.rawValue)
        }

        // Hotswap targets: open + arrange ALL, then hide every inactive app (URL targets
        // share the browser window, so they are surfaced by tab rather than hidden).
        guard let toggle = layout.quickToggle else { return }
        let frameRaw = toggle.frame.rawValue
        let activeRef = session.quickToggle?.activeRef ?? toggle.targets.first?.ref
        for target in toggle.targets {
            await surface(target.ref, kind: target.kind)
            await arrange(target.ref, kind: target.kind, frameRaw)
        }
        let activeBundle = activeRef.flatMap { appBundleByRef[$0] }
        let inactiveBundles = Set(toggle.targets.compactMap { target -> String? in
            guard target.kind == .app, let bundle = appBundleByRef[target.ref], bundle != activeBundle else {
                return nil
            }
            return bundle
        })
        if !inactiveBundles.isEmpty {
            _ = try? await workspaceWindows?.hideApplications(bundleIDs: Array(inactiveBundles))
        }
        // Bring the active hotswap forward and re-arrange it last so it shows in place.
        if let activeRef, let active = toggle.targets.first(where: { $0.ref == activeRef }) {
            await surface(active.ref, kind: active.kind)
            await arrange(active.ref, kind: active.kind, frameRaw)
        }
    }

    /// The browser bundle id to arrange for a layout URL window (NIC-142): Chrome for a
    /// profiled URL, else the default browser. nil when the ref is unknown or no default
    /// browser resolver is wired.
    private func urlBrowserBundleID(forURLRef ref: String) -> String? {
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        guard let entry = references?.urls[ref] else { return nil }
        return entry.profile != nil ? UserChromeProfileReferences.chromeBundleID : defaultBrowserBundleID?()
    }

    /// Exits layout mode: hides the session's app windows (permission-free, like
    /// "Windows Stored by Mode") and clears the session, emitting a null
    /// `layout.session.changed`. URL windows have no bundle id and are left open.
    private func closeLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let session = takeActiveLayoutSession() else {
            return ok(request, payload: CloseLayoutResult(closed: false))
        }
        let bundleIDs = session.appBundleIDs
        if let windows = workspaceWindows, !bundleIDs.isEmpty {
            _ = try? await windows.hideApplications(bundleIDs: bundleIDs)
        }
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: CloseLayoutResult(closed: true))
    }

    /// Swaps the dynamic quick-toggle slot to a target (NIC-142): hides the
    /// previously-shown target's app window and surfaces the pressed one — an app is
    /// re-opened/activated, a URL surfaces its tab through the runtime's shared
    /// tab-surfacing registry. No confirmation: the session was authorized when the
    /// layout opened (owner decision). A URL target that was previously shown cannot
    /// be hidden (its window is the shared browser), so the new target surfaces over it.
    private func toggleLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ToggleLayoutInput = decodePayload(request), !input.ref.isEmpty else {
            return invalidInput(request, "toggleLayout requires a ref.")
        }
        guard
            let session = peekActiveLayoutSession(),
            let toggle = session.quickToggle,
            let target = toggle.targets.first(where: { $0.ref == input.ref })
        else {
            // No active layout, no quick-toggle slot, or an unknown target.
            return ok(request, payload: ToggleLayoutResult(accepted: false))
        }
        if toggle.activeRef == input.ref {
            return ok(request, payload: ToggleLayoutResult(accepted: true))  // already shown
        }

        // Hide the previously-shown app target (permission-free); a URL prior can't
        // be hidden — the pressed target simply surfaces over the shared browser.
        if let previous = toggle.targets.first(where: { $0.ref == toggle.activeRef }),
           previous.kind == "app", let bundleID = previous.bundleID, let windows = workspaceWindows {
            _ = try? await windows.hideApplications(bundleIDs: [bundleID])
        }

        // Surface the pressed target directly (authorized once at open; no re-prompt),
        // then re-arrange it into the hotswap frame — the user may have moved it, and a
        // freshly surfaced window lands wherever the app put it, so force it back to the
        // slot on every swap (NIC-142).
        let frame = toggle.frame.flatMap(WindowFrame.init(rawValue:))
        switch target.kind {
        case "url":
            _ = try? await url?.open(urlID: target.ref)
            // A URL "window" is its browser: Chrome for a profiled URL, else the default.
            if let frame, let bundleID = urlBrowserBundleID(forURLRef: target.ref) {
                _ = try? await window?.arrange(bundleID: bundleID, frame: frame, display: .primary)
            }
        default:
            _ = try? await app?.open(appID: target.ref)
            if let frame, let bundleID = target.bundleID {
                _ = try? await window?.arrange(bundleID: bundleID, frame: frame, display: .primary)
            }
        }

        let updated = session.withActiveToggle(input.ref)
        setActiveLayoutSession(updated)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: updated.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ToggleLayoutResult(accepted: true))
    }

    /// Pins an app/URL reference as a quick-toggle target on a mode's layout
    /// (NIC-142) and persists it through the validated config-override path, so the
    /// pin survives restarts and drives the next open. When a session for that mode
    /// is active, the new target appears in the bar immediately. Requires the layout
    /// to already have a dynamic slot (the frame the pinned window would occupy).
    private func pinLayoutWindow(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: PinLayoutWindowInput = decodePayload(request),
              !input.modeId.isEmpty, !input.ref.isEmpty else {
            return invalidInput(request, "pinLayoutWindow requires a modeId and ref.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Pinning requires a durable workspace."
            )
        }
        guard let layout = resolveLayout(modeID: input.modeId) else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "no_layout",
                message: "Mode \"\(input.modeId)\" has no authored layout."
            )
        }
        guard let toggle = layout.quickToggle else {
            return ok(request, payload: PinLayoutWindowResult(
                accepted: false, errors: ["This layout has no dynamic slot to pin a window to."]
            ))
        }

        // Resolve the ref's kind from the reference catalog — this is also the
        // existence check (an id in neither catalog cannot be pinned).
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace.stateRoot
        )
        let kind: Kind
        if references?.apps[input.ref] != nil {
            kind = .app
        } else if references?.urls[input.ref] != nil {
            kind = .url
        } else {
            return ok(request, payload: PinLayoutWindowResult(
                accepted: false, errors: ["\"\(input.ref)\" is not a configured app or URL reference."]
            ))
        }

        // Already a target → accepted no-op (idempotent pin).
        if toggle.targets.contains(where: { $0.ref == input.ref }) {
            return ok(request, payload: PinLayoutWindowResult(accepted: true, errors: []))
        }

        let newLayout = Layout(
            display: layout.display,
            quickToggle: QuickToggle(frame: toggle.frame, targets: toggle.targets + [Target(kind: kind, ref: input.ref)]),
            windows: layout.windows
        )
        // Preserve any existing override fields (e.g. pinned quick apps) — the
        // override file replaces wholesale, so a layout-only write must not drop them.
        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions,
            id: input.modeId,
            layout: encodePayload(newLayout),
            quickApps: existing?.quickApps,
            schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            refreshActiveLayoutSession(modeID: input.modeId, layout: newLayout)
            return ok(request, payload: PinLayoutWindowResult(accepted: true, errors: []))
        case let .rejected(errors):
            return ok(request, payload: PinLayoutWindowResult(accepted: false, errors: errors.map(\.message)))
        }
    }

    /// Adds a quick-toggle target to the ACTIVE layout session for this session only
    /// (NIC-142) — the bottom-bar "+" live add. Unlike `pinLayoutWindow` it does NOT
    /// persist to the override: the target lives in the in-memory session and is gone
    /// when the layout closes or the mode switches. Requires an active session with a
    /// dynamic slot; idempotent for a ref already present. No confirmation — the
    /// session was authorized when the layout opened.
    private func addLayoutTarget(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: AddLayoutTargetInput = decodePayload(request), !input.ref.isEmpty else {
            return invalidInput(request, "addLayoutTarget requires a ref.")
        }
        guard let session = peekActiveLayoutSession(), let toggle = session.quickToggle else {
            // No active layout or no dynamic slot to add into (a session-only add
            // cannot mint a slot).
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        // Already a target → accepted no-op, no re-emit (idempotent).
        if toggle.targets.contains(where: { $0.ref == input.ref }) {
            return ok(request, payload: AddLayoutTargetResult(accepted: true))
        }
        // Resolve the ref against the reference catalog — the existence check plus the
        // kind/label/bundle id the session window needs.
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        let window: LayoutSessionWindow
        if let entry = references?.apps[input.ref] {
            window = LayoutSessionWindow(ref: input.ref, kind: "app", label: entry.label, bundleID: entry.target)
        } else if let entry = references?.urls[input.ref] {
            window = LayoutSessionWindow(ref: input.ref, kind: "url", label: entry.label, bundleID: nil)
        } else {
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        guard let updated = session.withAddedToggleTarget(window) else {
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        setActiveLayoutSession(updated)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: updated.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: AddLayoutTargetResult(accepted: true))
    }

    /// Writes a full authored layout to a mode's override (NIC-142 authoring) — the
    /// Save side of the Settings layout editor. Validates every reference against the
    /// catalog and the structure through the same override write path; preserves any
    /// existing override fields (e.g. pinned quick apps).
    private func updateLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: UpdateLayoutInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "updateLayout requires a modeId and layout.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Authoring a layout requires a durable workspace."
            )
        }
        guard let layout = Layout.from(raw: input.layout) else {
            return ok(request, payload: UpdateLayoutResult(accepted: false, errors: ["The layout is malformed."]))
        }
        // Reference-existence: every window and toggle target must name a configured
        // app or URL reference (the same gate quick-app pinning uses).
        let known = configuredReferenceIDs()
        var unknown: Set<String> = []
        for window in layout.windows where !known.contains(window.ref) { unknown.insert(window.ref) }
        for target in layout.quickToggle?.targets ?? [] where !known.contains(target.ref) { unknown.insert(target.ref) }
        guard unknown.isEmpty else {
            return ok(request, payload: UpdateLayoutResult(
                accepted: false,
                errors: unknown.sorted().map { "\"\($0)\" is not a configured app or URL reference." }
            ))
        }

        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions, id: input.modeId, layout: input.layout,
            quickApps: existing?.quickApps, schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            refreshActiveLayoutSession(modeID: input.modeId, layout: layout)
            return ok(request, payload: UpdateLayoutResult(accepted: true, errors: []))
        case let .rejected(errors):
            return ok(request, payload: UpdateLayoutResult(accepted: false, errors: errors.map(\.message)))
        }
    }

    /// Proposes a layout from the currently-arranged windows (NIC-142 live capture):
    /// each visible app that resolves to a configured reference, snapped to the named
    /// frame it most occupies. The editor lets the user refine and Save (updateLayout).
    /// macOS-only — degrades honestly without the AX window capability.
    private func captureLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let window, let workspaceWindows else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "capture_unavailable",
                message: "Layout capture is available on the macOS host."
            )
        }
        let visible: WindowRect
        do {
            guard let frame = try await window.visibleFrame() else {
                return errorResponse(
                    request, category: .unavailableCapability,
                    code: "no_display", message: "No display is available to capture."
                )
            }
            visible = frame
        } catch {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "capture_denied",
                message: "Layout capture needs the Accessibility permission."
            )
        }

        let refByBundle = appReferencesByTarget()
        let visibleApps = (try? await workspaceWindows.visibleApplicationBundleIDs()) ?? []
        var windows: [CaptureWindow] = []
        for bundleID in visibleApps {
            guard let ref = refByBundle[bundleID] else { continue }  // configured references only
            guard let rect = try? await window.captureFrame(bundleID: bundleID) else { continue }
            let frame = WindowFrameGeometry.snap(rect, in: visible)
            windows.append(CaptureWindow(ref: ref, kind: "app", frame: frame.rawValue))
        }
        return ok(request, payload: CaptureLayoutResult(windows: windows))
    }

    /// The mode's effective layout (NIC-142): the override-merged layout when a
    /// workspace is bound (so a user's pins drive open), else the shipped layout.
    private func resolveLayout(modeID: String) -> Layout? {
        if let workspace, case let .activated(config) = ConfigLoader(workspace: workspace).load() {
            return config.mode(id: modeID)?.layout
        }
        return ModeLayoutCatalog.load(configDirectory: configDirectory)[modeID]
    }

    private func readOverride(modeID: String, workspace: WorkspacePaths) -> CerebralHelmModeOverride? {
        let url = workspace.overridesDirectory.appendingPathComponent("\(modeID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CerebralHelmModeOverride(data: data)
    }

    /// Rebuilds the active session for `modeID` from a changed layout, keeping the
    /// currently-shown quick-toggle target, and re-emits it.
    private func refreshActiveLayoutSession(modeID: String, layout: Layout) {
        guard let current = peekActiveLayoutSession(), current.modeID == modeID else { return }
        var refreshed = buildLayoutSession(modeID: modeID, layout: layout)
        if let active = current.quickToggle?.activeRef {
            refreshed = refreshed.withActiveToggle(active)
        }
        setActiveLayoutSession(refreshed)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: refreshed.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// Ends an active layout session without hiding windows (a mode switch already
    /// owns the outgoing mode's window behavior). No-op when none is active.
    private func endActiveLayoutSession() {
        guard takeActiveLayoutSession() != nil else { return }
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// Resolves an authored layout into a session: each window/toggle target's
    /// human label and (for apps) bundle id, looked up in the reference catalog.
    private func buildLayoutSession(modeID: String, layout: Layout) -> LayoutSession {
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        func resolve(ref: String, kind: Kind) -> LayoutSessionWindow {
            switch kind {
            case .app:
                let entry = references?.apps[ref]
                return LayoutSessionWindow(ref: ref, kind: "app", label: entry?.label ?? ref, bundleID: entry?.target)
            case .url:
                let entry = references?.urls[ref]
                return LayoutSessionWindow(ref: ref, kind: "url", label: entry?.label ?? ref, bundleID: nil)
            }
        }
        let windows = layout.windows.map { resolve(ref: $0.ref, kind: $0.kind) }
        let toggle = layout.quickToggle.flatMap { qt -> LayoutSessionToggle? in
            guard let first = qt.targets.first else { return nil }
            return LayoutSessionToggle(
                activeRef: first.ref,
                targets: qt.targets.map { resolve(ref: $0.ref, kind: $0.kind) },
                frame: qt.frame.rawValue
            )
        }
        return LayoutSession(modeID: modeID, windows: windows, quickToggle: toggle)
    }

    private func setActiveLayoutSession(_ session: LayoutSession?) {
        layoutLock.lock(); defer { layoutLock.unlock() }
        activeLayoutSession = session
    }

    private func takeActiveLayoutSession() -> LayoutSession? {
        layoutLock.lock(); defer { layoutLock.unlock() }
        let session = activeLayoutSession
        activeLayoutSession = nil
        return session
    }

    private func peekActiveLayoutSession() -> LayoutSession? {
        layoutLock.lock(); defer { layoutLock.unlock() }
        return activeLayoutSession
    }

    private func captureNote(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CaptureNoteInput = decodePayload(request), !input.title.isEmpty else {
            return invalidInput(request, "captureNote requires a title.")
        }
        // note.capture is a confirmation-gated local_write, so this enters the bus and
        // the disclosure is pushed to the UI. The note is written after the user
        // approves; the returned id is the command handle (see the captureNote contract
        // note — a synchronous noteId is not possible for a gated capture).
        let text = input.body.isEmpty ? input.title : "\(input.title)\n\(input.body)"
        let outcome = await runtime.submit("note \(text)", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        switch outcome {
        case let .completed(commandID, _, result):
            if let data = result?.output, let output = try? CerebralHelmNoteCaptureOutput(data: data) {
                return ok(request, payload: CaptureNoteResult(noteId: output.noteID))
            }
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case .rejected:
            return errorResponse(
                request, category: .invalidInput,
                code: "note_rejected", message: "The note could not be parsed."
            )
        }
    }

    private func runSpeedTest(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        // network.speed.test is a read_only tool — it never gates on confirmation,
        // so this resolves synchronously with the measurement (NIC-135). The bounded
        // ~30s networkQuality run happens inside runtime.submit; the caller awaits it
        // while the widget animates its ring.
        let outcome = await runtime.submit("speedtest", source: .dashboard)
        guard case let .completed(_, _, result) = outcome,
              let data = result?.output,
              let output = try? CerebralHelmNetworkSpeedTestOutput(data: data)
        else {
            // The tool could not run, or produced no parseable output: an honest
            // unavailable, never a fabricated figure.
            return ok(request, payload: SpeedTestResult(
                status: "unavailable", downloadMbps: nil, uploadMbps: nil, testedAt: nil
            ))
        }
        return ok(request, payload: SpeedTestResult(
            status: output.status.rawValue,
            downloadMbps: output.downloadMbps,
            uploadMbps: output.uploadMbps,
            testedAt: output.testedAt
        ))
    }

    /// Stores an API credential in the Keychain behind a logical reference (NIC-134). The value
    /// is trimmed of surrounding whitespace (a pasted key often carries a trailing newline) and
    /// written through ``SecretManaging/store(reference:value:)``; the response reports presence
    /// only — it never echoes the value, and the value never touches config or a log (FR-CFG-03,
    /// FR-OBS-03). A store overwrites in place, so re-entering a key corrects a wrong one.
    private func storeSecret(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: StoreSecretInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "storeSecret requires a reference.")
        }
        let value = input.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return invalidInput(request, "Enter a value to store.")
        }
        guard let secretStore else {
            return errorResponse(
                request, category: .unavailableCapability, code: "secret_store_unavailable",
                message: "Storing a secret requires the macOS host."
            )
        }
        do {
            try await secretStore.store(reference: input.reference, value: value)
            // Nudge any live consumer keyed on this secret (e.g. the releases producer) so the
            // widget reflects a just-entered key at once, not on its next slow tick (NIC-134).
            onSecretStored?(input.reference)
            return ok(request, payload: StoreSecretResult(reference: input.reference, stored: true))
        } catch {
            // Deliberately generic: never surface the value or a raw keychain diagnostic.
            return errorResponse(
                request, category: .unavailableCapability, code: "secret_store_failed",
                message: "That secret couldn't be stored. Check the reference name and try again."
            )
        }
    }

    /// Reports whether a logical secret reference is bound, without exposing the value (NIC-134) —
    /// so the settings field can honestly show "Set" vs "Not set" on load. A host without a secret
    /// store, or a resolve failure, reports `bound: false` (an honest "not set") rather than an
    /// error, so the field still renders.
    private func getSecretStatus(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SecretStatusInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "getSecretStatus requires a reference.")
        }
        guard let secretStore else {
            return ok(request, payload: SecretStatusResult(reference: input.reference, bound: false))
        }
        let resolution = try? await secretStore.resolve(reference: input.reference)
        return ok(request, payload: SecretStatusResult(
            reference: input.reference, bound: resolution?.isResolved ?? false
        ))
    }

    /// Removes a stored secret (NIC-133) — the "disconnect" path (e.g. Spotify's `spotify_oauth`
    /// blob, or clearing a provider key). Idempotent: deleting an absent reference reports
    /// `deleted: false` without erroring, so a disconnect on an already-disconnected account is a
    /// clean no-op. The value is never read or echoed.
    private func deleteSecret(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SecretStatusInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "deleteSecret requires a reference.")
        }
        guard let secretStore else {
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: false))
        }
        do {
            try await secretStore.delete(reference: input.reference)
            // Tell any consumer holding this grant in memory to drop it, so a disconnect is real
            // rather than cosmetic (see `onSecretDeleted`).
            onSecretDeleted?(input.reference)
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: true))
        } catch {
            // Absent (or an unreadable store) — nothing to remove, an honest idempotent no-op.
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: false))
        }
    }

    /// Runs the Spotify OAuth connect flow (NIC-133): opens the browser to Spotify's consent page,
    /// captures the redirect, exchanges the code, and persists the tokens to the Keychain — all
    /// inside the injected `spotifyConnect` closure (the Mac coordinator). The response reports only
    /// `connected` and the granted `scope`; the tokens never cross back. Failures degrade to an
    /// honest message and never leak a diagnostic: no Client ID / user declined → guidance; a
    /// Spotify rejection or timeout → a generic retry message.
    private func connectSpotify(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let spotifyConnect else {
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_unavailable",
                message: "Connecting Spotify requires the macOS host."
            )
        }
        do {
            let connection = try await spotifyConnect()
            return ok(request, payload: ConnectSpotifyResult(connected: true, scope: connection.scope))
        } catch let error as SpotifyPlaybackError {
            let message: String
            switch error {
            case .credentialsMissing:
                message = "Add your Spotify Client ID in Settings → Setup, then connect."
            case .notConnected:
                message = "Spotify didn't accept the connection. Please try connecting again."
            case .providerFailed:
                message = "Couldn't connect to Spotify. Please try again."
            }
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_failed", message: message
            )
        } catch {
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_failed",
                message: "Couldn't connect to Spotify. Please try again."
            )
        }
    }

    private func searchNotes(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SearchNotesInput = decodePayload(request), !input.text.isEmpty else {
            // An empty query yields no results rather than an error (empty search box).
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let outcome = await runtime.submit("search \(input.text)", source: .dashboard)
        guard
            case let .completed(_, _, result) = outcome,
            let data = result?.output,
            let output = try? CerebralHelmNoteSearchOutput(data: data)
        else {
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let hits = output.results.map {
            NoteHit(noteId: $0.noteID, title: $0.title, excerpt: $0.excerpt, path: $0.path)
        }
        return ok(request, payload: SearchNotesResult(results: hits))
    }

    // MARK: - App discovery + auto-mint (NIC-119/150/168)

    /// Suggestion ranking should know every installed app, not only the already
    /// referenced ones (design spec §5.5 "best matching installed application"),
    /// but a filesystem scan per keystroke is out of the question: at most one
    /// discovery per TTL, claimed up front so concurrent calls never double-scan.
    /// Minted references are durable, so the catalog stays warm across sessions.
    private static let appDiscoveryTTL: TimeInterval = 15 * 60
    private let appDiscoveryLock = NSLock()
    private var lastAppDiscovery: Date?

    private func claimAppDiscoverySlot() -> Bool {
        appDiscoveryLock.lock()
        defer { appDiscoveryLock.unlock() }
        if let last = lastAppDiscovery, Date().timeIntervalSince(last) < Self.appDiscoveryTTL {
            return false
        }
        // Claimed before the scan runs (and kept on failure), so a failing host
        // attempts at most once per TTL instead of on every keystroke.
        lastAppDiscovery = Date()
        return true
    }

    /// Synchronous on purpose: `NSLock` may not be taken directly inside an async
    /// function, so the async discovery path stamps through this helper.
    private func stampAppDiscovery() {
        appDiscoveryLock.lock()
        lastAppDiscovery = Date()
        appDiscoveryLock.unlock()
    }

    /// Runs the read-only `apps` discovery command and auto-mints references
    /// (owner decision, 2026-07-06): any discovered app that no reference targets
    /// gets one minted, then the shared reference catalog live-reloads so
    /// `open <minted-id>` — and its suggestion — resolves this session too
    /// (NIC-150): the parser and, on the macOS shell, the app.open target map
    /// both read the runtime's reference store. Returns nil on any failure —
    /// discovery is an enrichment, never a gate.
    private func discoverAndMintApps() async -> CerebralHelmAppsListOutput? {
        let outcome = await runtime.submit("apps", source: .dashboard)
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let data = result?.output,
            let output = try? CerebralHelmAppsListOutput(data: data)
        else {
            return nil
        }
        stampAppDiscovery()
        if let workspace {
            let shipped = (try? ReferenceCatalogLoader.load(configDirectory: configDirectory))
                .map { Array($0.apps.values) } ?? []
            UserAppReferences.mint(
                discovered: output.apps.map {
                    UserAppReferences.DiscoveredApp(bundleID: $0.bundleID, name: $0.name)
                },
                shipped: shipped,
                stateRoot: workspace.stateRoot
            )
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
        }
        return output
    }

    /// The suggestion-triggered variant (NIC-168): refresh only when this host can
    /// actually discover (capability available), there is a workspace to mint
    /// into, and the TTL elapsed. Pre-Mac and capability-degraded sessions skip
    /// entirely — no doomed `apps` submissions polluting command history.
    private func refreshAppCatalogForSuggestionsIfDue() async {
        let discoveryAvailable = capabilities.first { $0.id == "native.apps.list" }?.available == true
        guard workspace != nil, discoveryAvailable, claimAppDiscoverySlot() else { return }
        _ = await discoverAndMintApps()
    }

    /// Read-only application discovery (NIC-119): wraps the `apps` command so the
    /// More Apps picker rides the same command bus as every other input source,
    /// and unwraps the tool output for the dashboard. Pre-Mac (or on any tool
    /// failure) this is a structured unavailable — the picker renders honestly.
    private func listApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let output = await discoverAndMintApps() else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "apps_list_unavailable",
                message: "Application discovery is unavailable."
            )
        }
        // Join discovered apps onto the configured app references by bundle id
        // (the reference `target`). `referenceId` is the pinnable key: only a
        // discovered app backed by a configured reference may enter a mode's
        // quick-app slots (NIC-119 — no arbitrary paths, ever).
        let referencesByTarget = appReferencesByTarget()
        let apps = output.apps.map {
            DiscoveredApp(
                bundleId: $0.bundleID,
                name: $0.name,
                iconPng: $0.iconPNG,
                referenceId: referencesByTarget[$0.bundleID]
            )
        }
        return ok(request, payload: ListAppsResult(apps: apps, truncated: output.truncated))
    }

    /// Sets a mode's quick-app slots through the validated config-write path
    /// (NIC-119c): every id must name a configured app reference (existence
    /// check), then `ConfigOverrideWriter` writes the per-mode override and
    /// re-activates the layered config — a rejected candidate is rolled back on
    /// disk and reported, never half-applied. An applied write emits
    /// `mode.quickapps.changed` so every surface's tiles refresh immediately.
    private func updateQuickApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: UpdateQuickAppsInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "updateQuickApps requires a modeId and quickApps array.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Pinning requires a durable workspace."
            )
        }
        // A quick-app slot may hold any configured app or URL reference id (NIC-146):
        // a pinned URL is just another quick-app tile, so both catalogs are valid
        // pin targets. Arbitrary paths/URLs still can't enter — only ids that name a
        // reference the catalog already resolves.
        let known = configuredReferenceIDs()
        let unknown = input.quickApps.filter { !known.contains($0) }
        guard unknown.isEmpty else {
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: unknown.map { "\"\($0)\" is not a configured app or URL reference." }
            ))
        }

        // Preserve any existing override fields (e.g. an authored layout, NIC-142) —
        // the override file replaces wholesale, so a quick-apps write must not drop them.
        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions, id: input.modeId, layout: existing?.layout,
            quickApps: input.quickApps, schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            // Refresh every surface: a dedicated per-widget event carries the new
            // slots (NIC-149). `config.changed` cannot — its snapshot omits `modes`
            // and the dashboard ignores it when the active mode is unchanged.
            emit(BridgeEventFactory.quickAppsChangedEvent(
                modeId: input.modeId, quickApps: input.quickApps,
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: true, quickApps: input.quickApps, errors: []
            ))
        case let .rejected(errors):
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: errors.map(\.message)
            ))
        }
    }

    /// Configured app references keyed by their bundle-id target.
    private func appReferencesByTarget() -> [String: String] {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return [:]
        }
        return Dictionary(
            references.apps.values.map { ($0.target, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every configured reference id the parser resolves — app and URL, shipped and
    /// user-minted. This is the pinnable-id set (`updateQuickApps`, NIC-146) and the
    /// uniqueness domain a newly minted URL id must avoid, so a pinned URL's
    /// `open <id>` can never resolve ambiguously against an app of the same id.
    private func configuredReferenceIDs() -> Set<String> {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return []
        }
        return Set(references.apps.keys).union(references.urls.keys)
    }

    /// Mints a user URL reference through the same auto-minting mechanism as user
    /// app references (NIC-146): a user-entered URL becomes a configured reference,
    /// so it can then be pinned as a quick app through the validated write path. Only
    /// `http`/`https` URLs mint — never an arbitrary scheme. Requires a durable
    /// workspace (the state root the user catalog lives under).
    private func addUrlReference(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: AddUrlReferenceInput = decodePayload(request) else {
            return invalidInput(request, "addUrlReference requires a url.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "url_references_unavailable",
                message: "Adding a URL requires a durable workspace."
            )
        }
        switch UserURLReferences.add(
            url: input.url, label: input.label, profile: input.profile,
            existingIDs: configuredReferenceIDs(), stateRoot: workspace.stateRoot
        ) {
        case let .success(entry):
            // Live-reload the shared catalog so the minted id resolves this session:
            // the runtime's parser (`open <id>`) and — on the macOS shell — the
            // url.open capability map both read the same store (NIC-146). Without this
            // the URL would open only after a relaunch.
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
            // Kick off the favicon fetch now so the icon is ready by the time the
            // dashboard re-reads `listUrls` after pinning (NIC-147). The minted DTO
            // carries no icon yet — the tile shows its placeholder until it lands.
            warmFavicons([entry])
            return ok(request, payload: AddUrlReferenceResult(
                accepted: true,
                reference: urlReferenceDTO(entry, cache: faviconCache()),
                errors: []
            ))
        case let .failure(error):
            return ok(request, payload: AddUrlReferenceResult(
                accepted: false, reference: nil, errors: [Self.message(for: error)]
            ))
        }
    }

    private static func message(for error: UserURLReferences.AddError) -> String {
        switch error {
        case .emptyURL: return "Enter a URL to add."
        case .invalidURL: return "That doesn't look like a valid web address."
        case .unsupportedScheme: return "Only http and https web addresses can be added."
        case .invalidProfile: return "The Chrome profile can only contain letters, numbers, spaces, dots, hyphens, and underscores."
        }
    }

    /// The configured URL references (shipped + user-minted), sorted by label — the
    /// dashboard's read feed for rendering pinned URL tiles with their real labels
    /// (NIC-146). Apps have `listApps` discovery for this; URLs have no discovery,
    /// so this is their equivalent. Workspace-less hosts still see the shipped set.
    private func listUrls(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        let urls = (try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )).map { Array($0.urls.values) } ?? []
        let cache = faviconCache()
        let sorted = urls
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map { urlReferenceDTO($0, cache: cache) }
        // Warm any cold favicons in the background; a landed icon upgrades its tile
        // live via `mode.quickapps.changed` (NIC-147). The read returns immediately.
        warmFavicons(urls)
        return ok(request, payload: ListUrlsResult(urls: sorted))
    }

    // MARK: - Chrome profiles (NIC-151)

    /// The user's Chrome profiles for the profile dropdown + avatar badges (NIC-151):
    /// directory name (the `--profile-directory` value a reference stores), display
    /// name, and an optional avatar PNG. An empty list on a host without the
    /// capability (non-Mac, tests) — the UI then offers no profile choices.
    private func listChromeProfiles(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let profiles = (try? await chromeProfiles?.listProfiles()) ?? []
        // The pinned Chrome-profile app references (NIC-151), so the dashboard can
        // render a pinned "Chrome — Work" tile with its label + avatar (by matching
        // the reference's profile directory back to a discovered profile).
        let references = (try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )).map { catalog in
            catalog.apps.values
                .filter { $0.target == UserChromeProfileReferences.chromeBundleID && $0.profile != nil }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
                .map { AppReferenceDTO(id: $0.id, label: $0.label, target: $0.target, profile: $0.profile) }
        } ?? []
        return ok(request, payload: ChromeProfilesResult(
            profiles: profiles.map {
                ChromeProfileDTO(directory: $0.directory, name: $0.name, iconPng: $0.iconPNGBase64)
            },
            references: references
        ))
    }

    /// Lists the user's calendars for the Settings calendar→mode mapping (NIC-126). Requests
    /// Calendar access at point of use; a denied grant (or any read failure, or no provider) is an
    /// honest `authorized: false` with an empty list, which the Settings UI turns into a "grant
    /// Calendar access" prompt rather than a fabricated set of calendars.
    private func listCalendars(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let calendarProvider else {
            return ok(request, payload: CalendarsResult(authorized: false, calendars: []))
        }
        do {
            let calendars = try await calendarProvider.calendars()
            return ok(request, payload: CalendarsResult(
                authorized: true,
                calendars: calendars.map { CalendarDTO(id: $0.id, title: $0.title, colorHex: $0.colorHex) }
            ))
        } catch {
            return ok(request, payload: CalendarsResult(authorized: false, calendars: []))
        }
    }

    /// Creates a calendar event from the `create-event` Input form (quick-actions phase 3).
    ///
    /// Enters the command bus like every other action — the runtime evaluates policy, gates on
    /// confirmation, executes and emits lifecycle events. What is different is only that the input
    /// arrives already typed: there is no text grammar that could carry a title, two datetimes, a
    /// calendar and notes without becoming lossy, so this uses the runtime's structured entry
    /// point instead of a `rawInput` string.
    ///
    /// `calendar.createevent` is `external_write` but opts into the user-authored exemption, so a
    /// form the user filled in and submitted runs one-click; the same call from an agent still
    /// confirms with its values disclosed. When it does gate, the response carries the command id
    /// and the confirmation surfaces through the event stream, exactly as `captureNote` does.
    private func createCalendarEvent(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CreateCalendarEventInput = decodePayload(request),
              !input.title.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "createCalendarEvent requires a title.")
        }
        guard input.startsAt <= input.endsAt else {
            return invalidInput(request, "createCalendarEvent requires endsAt to be at or after startsAt.")
        }

        let draft = CalendarEventDraft(
            title: input.title.trimmingCharacters(in: .whitespaces),
            startsAt: input.startsAt,
            endsAt: input.endsAt,
            calendarID: input.calendarId,
            calendarTitle: input.calendarTitle,
            location: input.location,
            notes: input.notes
        )
        let outcome = await runtime.submit(
            intent: .createCalendarEvent(draft),
            source: .dashboard,
            summary: "Create calendar event \"\(draft.title)\""
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(commandID, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmCalendarCreateEventOutput(data: data) {
                return ok(request, payload: CreateCalendarEventResult(
                    eventId: output.eventID, calendarTitle: output.calendarTitle, awaitingConfirmation: false
                ))
            }
            // Reached the terminal without an event: the tool was unavailable, denied, or failed.
            // Report that honestly rather than returning a success shape with a command id in it.
            return errorResponse(
                request, category: .unavailableCapability,
                code: "calendar_event_not_created",
                message: "The event was not created (\(status.rawValue)). Calendar access is granted in System Settings."
            )
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CreateCalendarEventResult(
                eventId: commandID, calendarTitle: nil, awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "calendar_event_rejected", message: reason
            )
        }
    }

    /// Clones a repository into the projects root (quick-actions phase 4), from the `git-clone`
    /// Input form.
    ///
    /// Structured rather than a `clone <url>` text submit because the form carries an optional
    /// folder name, and no text grammar carries an optional second argument without becoming lossy
    /// about quoting. `git.clone` is `local_write`, so it runs one-click — but the gated path is
    /// still handled: "ask before all actions" re-arms confirmation over every tool, and reporting
    /// a clone as done while its confirmation is pending would be a lie.
    private func cloneRepository(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CloneRepositoryInput = decodePayload(request),
              !input.repositoryUrl.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "cloneRepository requires a repository URL.")
        }
        let url = input.repositoryUrl.trimmingCharacters(in: .whitespaces)
        let directory = input.directory?.trimmingCharacters(in: .whitespaces)

        let outcome = await runtime.submit(
            intent: .cloneRepository(url: url, directory: (directory?.isEmpty ?? true) ? nil : directory),
            source: .dashboard,
            summary: "Clone repository \(url)"
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(commandID, status, result):
            _ = commandID
            if let data = result?.output,
               let output = try? CerebralHelmGitCloneOutput(data: data) {
                return ok(request, payload: CloneRepositoryResult(
                    clonedPath: output.clonedPath,
                    repositoryName: output.clonedRepositoryName,
                    awaitingConfirmation: false
                ))
            }
            // No output means the tool was unavailable, denied, or failed — say so rather than
            // returning a success shape with no clone behind it.
            return errorResponse(
                request, category: .unavailableCapability,
                code: "repository_not_cloned",
                message: "The repository was not cloned (\(status.rawValue))."
            )
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CloneRepositoryResult(
                clonedPath: commandID, repositoryName: "", awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "clone_rejected", message: reason
            )
        }
    }

    /// Opens the native folder picker for the `git-clone` form's location field.
    ///
    /// The operation takes **no input**: a caller-supplied starting directory would be the first
    /// step toward a caller-chosen destination, which is exactly what the projects-root constraint
    /// exists to prevent. The host decides where the panel opens and refuses anything outside it,
    /// so what comes back is already inside the root or is honestly reported as refused.
    private func chooseFolderOperation(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let chooseFolder else {
            return ok(request, payload: FolderSelectionResult(
                folderPath: nil, relativeFolder: nil, cancelled: true, outsideRoot: false, available: false
            ))
        }
        let selection = await chooseFolder()
        return ok(request, payload: FolderSelectionResult(
            folderPath: selection.absolutePath,
            relativeFolder: selection.relativePath,
            cancelled: selection.cancelled,
            outsideRoot: selection.outsideRoot,
            available: true
        ))
    }

    /// Lists contacts and existing chats for the `send-text` recipient picker.
    ///
    /// Two grants sit behind it — Contacts and Automation — and each can be refused independently,
    /// so a partial list is a normal outcome rather than a failure. The contacts never leave the
    /// machine: they cross to a local webview so the user can pick one.
    private func listMessageRecipients(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let messageRecipients else {
            return ok(request, payload: MessageRecipientsResult(recipients: [], available: false, reason: nil))
        }
        do {
            let found = try await messageRecipients()
            return ok(request, payload: MessageRecipientsResult(
                recipients: found.map(MessageRecipientsResult.Recipient.init), available: true, reason: nil
            ))
        } catch {
            return ok(request, payload: MessageRecipientsResult(
                recipients: [], available: true,
                reason: "Contacts couldn\u{2019}t be read. Grant Contacts access in System Settings."
            ))
        }
    }

    /// Sends one message from the `send-text` form.
    ///
    /// **This one is expected to gate.** `messages.send` takes no user-authored exemption, so the
    /// normal outcome here is `awaitingConfirmation` — the response says so, and the form reports
    /// that it needs confirming rather than that it was sent.
    private func sendMessage(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SendMessageInput = decodePayload(request),
              !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return invalidInput(request, "sendMessage requires a message.")
        }
        guard !input.target.trimmingCharacters(in: .whitespaces).isEmpty else {
            return invalidInput(request, "sendMessage requires a recipient.")
        }

        let outcome = await runtime.submit(
            intent: .sendMessage(MessageDraft(
                body: input.body.trimmingCharacters(in: .whitespacesAndNewlines),
                target: input.target,
                targetKind: input.targetKind == "chat" ? "chat" : "participant",
                targetName: input.targetName,
                groupSize: input.groupSize
            )),
            source: .dashboard,
            // The summary names the recipient but NOT the body: it is the line that reaches the
            // command log, and the body belongs only in the confirmation the user reads.
            summary: "Send a message to \(input.targetName ?? input.target)"
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(_, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmMessagesSendOutput(data: data), output.messageSent {
                return ok(request, payload: SendMessageResult(
                    targetName: output.messageTargetName ?? input.targetName ?? input.target,
                    sent: true, awaitingConfirmation: false
                ))
            }
            let denied = result?.status == .denied
            return errorResponse(
                request, category: denied ? .permissionDenied : .unavailableCapability,
                code: denied ? "messages_permission_required" : "message_not_sent",
                message: denied
                    ? "Messages refused. Allow CerebralHelm to control Messages in System Settings → Privacy & Security → Automation."
                    : "The message was not sent (\(status.rawValue))."
            )
        case .awaitingConfirmation:
            // The expected path, not an error: every send is confirmed.
            return ok(request, payload: SendMessageResult(
                targetName: input.targetName ?? input.target, sent: false, awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "message_rejected", message: reason
            )
        }
    }

    /// Lists current sports events for the `check-scoreboard` picker and the report it opens.
    ///
    /// **One operation serves both** because they read the same document: the picker shows the
    /// names, the report shows the detail already inside them. Fetching twice would pay golf's
    /// megabyte twice for data the host had in hand. The report re-calls it on submit so the
    /// scores are current at the moment the user asked for them — the snapshot semantics the
    /// action was designed around.
    private func listSportsEvents(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let sportsEvents else {
            return ok(request, payload: SportsEventsResult(events: [], available: false, reason: nil))
        }
        do {
            let events = try await sportsEvents()
            return ok(request, payload: SportsEventsResult(
                events: events.map(SportsEventsResult.Event.init), available: true, reason: nil
            ))
        } catch {
            // Unreadable is not the same fact as "nothing is on today", and the picker says which.
            let reason: String
            if case let SportsScoreboardError.providerFailed(message) = error {
                reason = message
            } else {
                reason = "Scores couldn't be read right now."
            }
            return ok(request, payload: SportsEventsResult(events: [], available: true, reason: reason))
        }
    }

    /// Lists the Linear workspace for the `create-ticket` form's dropdowns.
    ///
    /// A read that never touches the command bus, like `listCalendars`: the user is filling in a
    /// form, not performing an action, and routing option-loading through the executor would put a
    /// command in the log every time a form opens.
    private func listLinearOptions(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let linearWorkspace else {
            return ok(request, payload: LinearOptionsResult(teams: [], available: false, reason: nil))
        }
        do {
            let workspace = try await linearWorkspace()
            return ok(request, payload: LinearOptionsResult(
                teams: workspace.teams.map(LinearOptionsResult.Team.init),
                available: true,
                reason: nil
            ))
        } catch {
            // An unreadable workspace is reported as such rather than as an empty one: "you have no
            // teams" and "we could not read your teams" are different facts, and the form says which.
            return ok(request, payload: LinearOptionsResult(
                teams: [], available: true, reason: "\(error)"
            ))
        }
    }

    /// Reads one project's standing in the active cycle for the project detail window (NIC-221).
    ///
    /// A read that never touches the command bus, for the same reason as `listLinearOptions`: the
    /// user is looking at a window, not acting on the world, and routing it through the executor
    /// would put a command in the log every time a project is opened.
    ///
    /// Three distinguishable outcomes, none of which may collapse into another:
    /// `available: false` (this host has no Linear client at all), a populated `reason` (the read
    /// was attempted and failed), and `matchedProject: nil` (the name matches no project — which
    /// would otherwise render exactly like an empty cycle).
    private func getLinearProjectCycle(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: LinearProjectCycleInput = decodePayload(request),
              !input.project.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "getLinearProjectCycle requires a project name.")
        }
        guard let linearProjectCycle else {
            return ok(request, payload: LinearProjectCycleResult.unavailable)
        }
        do {
            return ok(request, payload: LinearProjectCycleResult(try await linearProjectCycle(input.project)))
        } catch {
            // "We could not read it" is not "there is nothing in it" — the section says which.
            return ok(request, payload: LinearProjectCycleResult.failed(reason: "\(error)"))
        }
    }

    /// Creates a project folder from the `create-project` form.
    ///
    /// Structured for the same reason as the others: a name, a location, a summary and an
    /// importance do not survive a text grammar without becoming lossy about quoting.
    private func scaffoldProject(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ScaffoldProjectInput = decodePayload(request),
              !input.name.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "scaffoldProject requires a name.")
        }
        let name = input.name.trimmingCharacters(in: .whitespaces)
        let location = input.location?.trimmingCharacters(in: .whitespaces)

        let outcome = await runtime.submit(
            intent: .scaffoldProject(
                name: name,
                location: (location?.isEmpty ?? true) ? nil : location,
                summary: input.summary,
                importance: input.importance
            ),
            source: .dashboard,
            summary: "Create project \"\(name)\""
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(_, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmProjectScaffoldOutput(data: data) {
                return ok(request, payload: ScaffoldProjectResult(
                    projectPath: output.projectPath, awaitingConfirmation: false
                ))
            }
            return errorResponse(
                request, category: .unavailableCapability,
                code: "project_not_created",
                message: "The project was not created (\(status.rawValue))."
            )
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: ScaffoldProjectResult(
                projectPath: commandID, awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "project_rejected", message: reason
            )
        }
    }

    /// Creates one Spotify playlist from the `create-playlist` form.
    ///
    /// A `403` from Spotify is the **scope gap**, not a broken account: the playlist scopes were
    /// added alongside this action, so a grant made earlier still works for playback and is refused
    /// here. That is reported as its own code so the form can say "reconnect" rather than
    /// "something went wrong".
    private func createSpotifyPlaylist(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CreateSpotifyPlaylistInput = decodePayload(request),
              !input.name.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "createSpotifyPlaylist requires a name.")
        }
        let name = input.name.trimmingCharacters(in: .whitespaces)

        let outcome = await runtime.submit(
            intent: .createSpotifyPlaylist(
                name: name,
                description: input.description,
                // Absent means private: Spotify defaults this to true, and publishing to someone's
                // profile because a field was omitted is not a default worth inheriting.
                isPublic: input.isPublic ?? false
            ),
            source: .dashboard,
            summary: "Create Spotify playlist \"\(name)\""
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(_, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmSpotifyCreatePlaylistOutput(data: data) {
                return ok(request, payload: CreateSpotifyPlaylistResult(
                    playlistId: output.playlistID,
                    name: output.playlistName,
                    url: output.playlistURL,
                    opened: output.playlistOpened ?? false,
                    awaitingConfirmation: false,
                    needsReconnect: false
                ))
            }
            // `denied` is specifically the scope gap or a dead authorization, which the user can
            // fix in one step — so it is reported apart from a generic failure.
            let denied = result?.status == .denied
            return errorResponse(
                request, category: denied ? .permissionDenied : .unavailableCapability,
                code: denied ? "spotify_reconnect_required" : "playlist_not_created",
                message: denied
                    ? "Spotify refused the write. Reconnect Spotify under Settings → Setup to allow playlists."
                    : "The playlist was not created (\(status.rawValue))."
            )
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CreateSpotifyPlaylistResult(
                playlistId: commandID, name: name, url: nil, opened: false,
                awaitingConfirmation: true, needsReconnect: false
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "playlist_rejected", message: reason
            )
        }
    }

    /// Creates one Linear issue from the `create-ticket` form.
    ///
    /// Structured, like `createCalendarEvent`, because no text grammar carries a title, a body, a
    /// team, a project, a label and a priority without becoming lossy about quoting. The display
    /// names ride along purely so a confirmation can name the destination in words.
    private func createLinearIssue(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CreateLinearIssueInput = decodePayload(request),
              !input.title.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "createLinearIssue requires a title.")
        }
        guard !input.teamId.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Never inferred: a workspace can have several teams, and picking one would file the
            // ticket somewhere the user did not choose.
            return invalidInput(request, "createLinearIssue requires a team.")
        }

        let draft = LinearIssueDraft(
            title: input.title.trimmingCharacters(in: .whitespaces),
            description: input.description,
            teamID: input.teamId,
            teamName: input.teamName,
            projectID: input.projectId,
            projectName: input.projectName,
            labelIDs: input.labelIds ?? [],
            labelNames: input.labelNames ?? [],
            priority: input.priority
        )
        let outcome = await runtime.submit(
            intent: .createLinearIssue(draft),
            source: .dashboard,
            summary: "Create Linear issue \"\(draft.title)\""
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(_, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmLinearCreateIssueOutput(data: data) {
                return ok(request, payload: CreateLinearIssueResult(
                    identifier: output.issueIdentifier, url: output.issueURL, awaitingConfirmation: false
                ))
            }
            return errorResponse(
                request, category: .unavailableCapability,
                code: "linear_issue_not_created",
                message: "The ticket was not created (\(status.rawValue))."
            )
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CreateLinearIssueResult(
                identifier: commandID, url: nil, awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "linear_issue_rejected", message: reason
            )
        }
    }

    /// Reports the Canvas ingest connection state (NIC-132): the loopback endpoint + pairing token to
    /// paste into the Chrome extension, and the last scrape's age/counts. A host without the Mac
    /// ingest store reports `available: false`, so the settings surface shows "requires the macOS
    /// host" rather than a broken pairing panel.
    private func getCanvasStatus(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let canvasStatus else {
            return ok(request, payload: CanvasStatusResult.unavailable)
        }
        return ok(request, payload: CanvasStatusResult(await canvasStatus()))
    }

    /// Disconnects Canvas (NIC-132): purges the scraped data and rotates the ingest token, so the old
    /// token stops working and the extension must be re-paired. Returns the fresh (empty) state.
    private func resetCanvas(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let canvasReset else {
            return ok(request, payload: CanvasStatusResult.unavailable)
        }
        return ok(request, payload: CanvasStatusResult(await canvasReset()))
    }

    /// Hides or unhides a scraped Canvas item (NIC-132): the item is filtered out of / restored to the
    /// School widgets, and the fresh status (with each item's hidden flag) is returned so the settings
    /// list reconciles in one round trip.
    private func setCanvasItemHidden(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let canvasSetHidden else {
            return ok(request, payload: CanvasStatusResult.unavailable)
        }
        guard let input: SetCanvasHiddenInput = decodePayload(request) else {
            return invalidInput(request, "setCanvasItemHidden requires an item id and a hidden flag.")
        }
        return ok(request, payload: CanvasStatusResult(await canvasSetHidden(input.id, input.hidden)))
    }

    /// Lists the durable notes for the Setup → Library card (NIC-162).
    ///
    /// Goes through the bus like `searchNotes`, so the settings surface reads the
    /// knowledge base through the same `note.list` tool an assistant would — there
    /// is no second, UI-only read path. The reported `total` is every note under
    /// the root regardless of `limit`, so a card that shows the few most recent
    /// notes still states honestly how many there are.
    ///
    /// An unreachable root is `available: false` rather than an empty list: "no
    /// notes yet" and "your knowledge root is gone" must never look the same.
    private func listNotes(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let input: ListNotesInput? = decodePayload(request)
        let limit = input?.limit
        let outcome = await runtime.submit(
            limit.map { "notes-list \($0)" } ?? "notes-list", source: .dashboard
        )
        guard
            case let .completed(_, _, result) = outcome,
            result?.error == nil,
            let data = result?.output,
            let output = try? CerebralHelmNoteListOutput(data: data)
        else {
            return ok(request, payload: ListNotesResult.unavailable)
        }
        return ok(request, payload: ListNotesResult(output))
    }

    /// Lists the course notebooks under the school folder (quick actions phase 5).
    ///
    /// The `take-notes` picker's first stage. It reports only what is **on disk** — the live
    /// Canvas courses are already in dashboard state, and the surface merges the two. Keeping them
    /// apart is what lets last semester's notes stay reachable after Canvas stops listing a course.
    ///
    /// An unreadable knowledge root is `available: false` rather than an empty list, for the same
    /// reason `listNotes` distinguishes them: "no courses yet" and "your vault is gone" must never
    /// look the same.
    private func listCourses(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let input: ListCoursesInput? = decodePayload(request)
        let outcome = await runtime.submit(
            input?.limit.map { "courses-list \($0)" } ?? "courses-list", source: .dashboard
        )
        guard
            case let .completed(_, _, result) = outcome,
            result?.error == nil,
            let data = result?.output,
            let output = try? CerebralHelmCourseListOutput(data: data)
        else {
            return ok(request, payload: ListCoursesResult.unavailable)
        }
        return ok(request, payload: ListCoursesResult(output))
    }

    /// Creates one templated note in a course (quick actions phase 5), from the `take-notes` picker.
    ///
    /// Structured rather than a text submit because it carries two free-text fields, either of
    /// which can contain spaces — the same reason `create-event` and `create-ticket` skip parsing.
    ///
    /// The caller names a **course**, never a folder: the notebook derives the folder inside the
    /// school root and mints it on first use, so a note can only ever land there. `local_write`
    /// runs one-click, but the gated path is still handled — "ask before all actions" re-arms
    /// confirmation over every tool, and reporting a note as written while its confirmation is
    /// pending would be a lie.
    private func createCourseNote(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CreateCourseNoteInput = decodePayload(request),
              !input.course.trimmingCharacters(in: .whitespaces).isEmpty,
              !input.title.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "createCourseNote requires a course and a title.")
        }
        let course = input.course.trimmingCharacters(in: .whitespaces)
        let title = input.title.trimmingCharacters(in: .whitespaces)

        let outcome = await runtime.submit(
            intent: .createCourseNote(course: course, title: title),
            source: .dashboard,
            summary: "Create the note \"\(title)\" in \(course)"
        )
        registerAwaitingConfirmation(outcome)

        switch outcome {
        case let .completed(_, status, result):
            if let data = result?.output,
               let output = try? CerebralHelmCourseNoteCreateOutput(data: data) {
                return ok(request, payload: CreateCourseNoteResult(
                    course: output.noteCourse,
                    path: output.notePath,
                    title: output.noteTitle,
                    created: output.noteCreated,
                    awaitingConfirmation: false
                ))
            }
            return errorResponse(
                request, category: .unavailableCapability, code: "course_note_not_created",
                message: "The note was not created (\(status.rawValue)). Your notes are unchanged."
            )
        case let .awaitingConfirmation(commandID, _, _):
            // No path yet — nothing has been written. The surface must not offer to open one.
            return ok(request, payload: CreateCourseNoteResult(
                course: course, path: commandID, title: title,
                created: false, awaitingConfirmation: true
            ))
        case let .rejected(reason, _):
            return errorResponse(
                request, category: .invalidInput, code: "course_note_rejected", message: reason
            )
        }
    }

    /// The unread messages themselves, for the email report (Gmail integration).
    ///
    /// On demand only. Each message costs a request, so this is deliberately not a channel the
    /// dashboard samples — the count on the daily brief comes from a single label read instead.
    ///
    /// A failure is reported with its own reason rather than an empty list: "no unread mail" and
    /// "we could not read your mail" are opposite facts, and rendering both as an empty report
    /// would tell the user they were caught up when nobody looked.
    private func listUnreadMail(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let unreadMail else {
            return ok(request, payload: UnreadMailResult.unavailable(state: "not-connected", reason: nil))
        }
        let input: ListUnreadMailInput? = decodePayload(request)
        do {
            let messages = try await unreadMail(input?.limit ?? 5)
            return ok(request, payload: UnreadMailResult(messages))
        } catch let error as MailError {
            switch error {
            case .notConnected:
                return ok(request, payload: UnreadMailResult.unavailable(state: "not-connected", reason: nil))
            case .reconnectRequired:
                return ok(request, payload: UnreadMailResult.unavailable(
                    state: "reconnect", reason: "Gmail needs reconnecting — Settings → Setup."
                ))
            case let .providerFailed(detail):
                return ok(request, payload: UnreadMailResult.unavailable(state: "unavailable", reason: detail))
            }
        } catch {
            return ok(request, payload: UnreadMailResult.unavailable(
                state: "unavailable", reason: error.localizedDescription
            ))
        }
    }

    /// Runs the Gmail OAuth connect, or disconnects (Gmail integration).
    ///
    /// One operation with a `disconnect` flag rather than two, because they are the two halves of
    /// one control and the surface always renders exactly one of them.
    ///
    /// **A connect that returns no refresh token is reported as a problem, not a success.** Such a
    /// grant works for an hour and then cannot renew itself — the failure `access_type=offline` and
    /// `prompt=consent` exist to prevent — and telling the user it worked would leave them to
    /// discover it an hour later with no idea why.
    private func connectGmail(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let input: ConnectGmailInput? = decodePayload(request)
        if input?.disconnect == true {
            guard let gmailDisconnect else {
                return ok(request, payload: ConnectGmailResult(connected: false, scope: nil, canRefresh: false))
            }
            try? await gmailDisconnect()
            return ok(request, payload: ConnectGmailResult(connected: false, scope: nil, canRefresh: false))
        }
        guard let gmailConnect else {
            return errorResponse(
                request, category: .unavailableCapability, code: "gmail_connect_unavailable",
                message: "Connecting Gmail requires the macOS host."
            )
        }
        do {
            let connection = try await gmailConnect()
            return ok(request, payload: ConnectGmailResult(
                connected: true, scope: connection.scope, canRefresh: connection.canRefresh
            ))
        } catch let error as GmailConnectError {
            return errorResponse(
                request, category: error.category, code: error.code, message: error.message
            )
        } catch {
            return errorResponse(
                request, category: .providerFailure, code: "gmail_connect_failed",
                message: "Couldn\u{2019}t connect Gmail. Please try again."
            )
        }
    }

    /// Runs the system health checks, streaming each result as it lands (quick actions phase 5).
    ///
    /// **Streamed rather than awaited.** The inventory reaches several third parties, so a run
    /// takes seconds — long enough that a surface waiting on one response would show nothing at
    /// all while the interesting part (which checks exist) is already known. The operation returns
    /// the first snapshot, every check `pending`, and each completion arrives as a
    /// `system.checks.changed` event carrying the **whole** set.
    ///
    /// One run at a time: a second press while a run is in flight is answered with the run already
    /// going rather than starting a competing one, because two runs would interleave their
    /// emissions and the reader would watch rows flicker between two truths.
    private func runSystemChecks(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let systemChecks else {
            return ok(request, payload: SystemChecksResult.unavailable)
        }
        let checks = systemChecks()
        guard !checks.isEmpty else {
            return ok(request, payload: SystemChecksResult.unavailable)
        }
        guard claimSystemCheckRun() else {
            return ok(request, payload: SystemChecksResult(started: true, checkCount: checks.count))
        }

        // Detached from the request: the response returns now and the emissions continue.
        Task { [weak self] in
            for await run in HealthCheckRunner().run(checks) {
                guard let self else { return }
                self.emit(BridgeEventFactory.systemChecksEvent(
                    run: run, id: BridgeEventFactory.newEventID(), timestamp: Date()
                ))
                if run.complete { self.releaseSystemCheckRun() }
            }
        }
        return ok(request, payload: SystemChecksResult(started: true, checkCount: checks.count))
    }

    /// Composes a Report with a model, streaming the blocks as they arrive (NIC-228, NIC-253).
    ///
    /// **Everything the model reads is gathered on this side of the bridge.** The request carries a
    /// report id and nothing else: the Assembler runs here, so message previews, profile notes and
    /// sprint detail never enter the web layer at all. What goes back is the composed document —
    /// prose the user is about to be shown anyway.
    ///
    /// **Streamed rather than awaited**, exactly like the health-check run above and for the same
    /// reason, only more so: a composition takes around nine seconds, and nine seconds of silence and
    /// nine seconds of visible arrival feel nothing alike. The operation returns as soon as the
    /// composition has started; each block reaches the surface as a `report.composition.changed`
    /// event carrying the whole set so far, and a terminal emission carries the outcome.
    ///
    /// One composition at a time per report: a second press while one is in flight is answered with
    /// the one already going rather than starting a competitor, because two would interleave their
    /// emissions and the reader would watch the brief rewrite itself between two truths.
    private func composeReport(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ComposeReportInput = decodePayload(request),
              !input.reportID.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return invalidInput(request, "composeReport requires a reportId.")
        }
        guard let composeReport else {
            return ok(request, payload: ComposeReportResult.unavailable(
                "No model is configured on this machine."
            ))
        }
        let reportID = input.reportID
        guard claimComposition(reportID) else {
            return ok(request, payload: ComposeReportResult.started)
        }

        // Detached from the request: the response returns now and the emissions continue.
        Task { [weak self] in
            let started = Date()
            let firstBlockAt = FirstBlockClock()
            // Bound once, outside the progress closure. `weak self` cannot be captured by a
            // `@Sendable` closure that runs concurrently, and a strong reference here is bounded by
            // the composition itself rather than held indefinitely.
            guard let session = self else { return }

            let outcome = await composeReport(reportID) { blocks in
                firstBlockAt.markIfUnset(Date())
                session.emit(BridgeEventFactory.reportCompositionEvent(
                    reportID: reportID, blocks: blocks, complete: false,
                    id: BridgeEventFactory.newEventID(), timestamp: Date()
                ))
            }

            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let firstBlockMs = firstBlockAt.milliseconds(since: started)

            switch outcome {
            case let .composed(report):
                session.emit(BridgeEventFactory.reportCompositionEvent(
                    reportID: reportID, blocks: report.document.blocks, complete: true,
                    firstBlockMs: firstBlockMs, totalMs: elapsed,
                    id: BridgeEventFactory.newEventID(), timestamp: Date()
                ))
            case let .failed(failure):
                // The reader-facing sentence, never the decoder's complaint, and NO blocks: whatever
                // streamed before a failure came from an attempt that did not survive validation, so
                // showing it as final would render a document the composer rejected.
                session.emit(BridgeEventFactory.reportCompositionEvent(
                    reportID: reportID, blocks: [], complete: true,
                    reason: failure.readerFacingMessage,
                    firstBlockMs: firstBlockMs, totalMs: elapsed,
                    id: BridgeEventFactory.newEventID(), timestamp: Date()
                ))
            }
            session.releaseComposition(reportID)
        }

        return ok(request, payload: ComposeReportResult.started)
    }

    /// Claims the single composition slot for `reportID`, or reports that one is already going.
    private func claimComposition(_ reportID: String) -> Bool {
        compositionLock.lock()
        defer { compositionLock.unlock() }
        return composingReports.insert(reportID).inserted
    }

    private func releaseComposition(_ reportID: String) {
        compositionLock.lock()
        composingReports.remove(reportID)
        compositionLock.unlock()
    }

    /// Claims the single run slot, or reports that one is already going.
    private func claimSystemCheckRun() -> Bool {
        systemCheckLock.lock()
        defer { systemCheckLock.unlock() }
        if systemCheckRunning { return false }
        systemCheckRunning = true
        return true
    }

    private func releaseSystemCheckRun() {
        systemCheckLock.lock()
        systemCheckRunning = false
        systemCheckLock.unlock()
    }

    /// Rebuilds the derived note search index from the durable Markdown (NIC-163).
    ///
    /// The user reaches this from Setup → Library after editing notes outside
    /// CerebralHelm — the index only learns about those files when it is rebuilt.
    /// It is safe by construction: the Markdown is the source of truth, so the
    /// worst a failed rebuild costs is search results, never a note. A failure is
    /// reported as one; the response never claims a rebuild that did not happen.
    private func rebuildKnowledgeIndex(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let knowledgeRebuild else {
            return ok(request, payload: KnowledgeRebuildResult.unavailable)
        }
        do {
            return ok(request, payload: KnowledgeRebuildResult(try await knowledgeRebuild()))
        } catch {
            return errorResponse(
                request, category: .providerFailure, code: "knowledge_rebuild_failed",
                message: "The search index could not be rebuilt. Your notes are unchanged."
            )
        }
    }

    /// Mints an app reference that opens Google Chrome in a specific profile (NIC-151),
    /// so a Chrome profile can be pinned as a quick app the same way any app is. The
    /// minted reference targets `com.google.Chrome` and carries the profile directory,
    /// so `app.open` launches it with `--profile-directory` (NIC-151 increment 3).
    private func addChromeProfileReference(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: AddChromeProfileInput = decodePayload(request) else {
            return invalidInput(request, "addChromeProfileReference requires a profile directory.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "chrome_profiles_unavailable",
                message: "Pinning a Chrome profile requires a durable workspace."
            )
        }
        switch UserChromeProfileReferences.add(
            directory: input.directory, name: input.name,
            existingIDs: configuredReferenceIDs(), stateRoot: workspace.stateRoot
        ) {
        case let .success(entry):
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
            return ok(request, payload: AddChromeProfileResult(
                accepted: true,
                reference: AppReferenceDTO(id: entry.id, label: entry.label, target: entry.target, profile: entry.profile),
                errors: []
            ))
        case let .failure(error):
            return ok(request, payload: AddChromeProfileResult(
                accepted: false, reference: nil, errors: [Self.message(for: error)]
            ))
        }
    }

    private static func message(for error: UserChromeProfileReferences.AddError) -> String {
        switch error {
        case .emptyDirectory: return "Choose a Chrome profile to pin."
        case .invalidProfile: return "That Chrome profile name isn't valid."
        }
    }

    // MARK: - Favicons (NIC-147)

    private func faviconCache() -> FaviconCache? {
        workspace.map { FaviconCache(directory: $0.faviconCacheDirectory) }
    }

    private func urlReferenceDTO(_ entry: ReferenceEntry, cache: FaviconCache?) -> UrlReferenceDTO {
        UrlReferenceDTO(
            id: entry.id, label: entry.label, target: entry.target,
            iconPng: cache?.icon(forTarget: entry.target)?.base64EncodedString(),
            profile: entry.profile
        )
    }

    /// Fetches, in the background, the favicon for every reference whose origin has
    /// no cached hit or fresh miss — skipping origins already in flight. On success
    /// the PNG is cached and a `mode.quickapps.changed` event nudges the tiles to
    /// re-read `listUrls` (NIC-147 owner decision: reuse the per-widget event, so a
    /// freshly pinned URL shows its placeholder at once and upgrades once fetched).
    /// No-op without a favicon capability or a durable workspace.
    private func warmFavicons(_ references: [ReferenceEntry]) {
        guard let capability = faviconCapability, let cache = faviconCache() else { return }
        // One representative target per cold origin (favicons are per-origin).
        var targetByOrigin: [String: String] = [:]
        for entry in references {
            guard
                let origin = FaviconCache.origin(forTarget: entry.target),
                cache.needsFetch(forTarget: entry.target),
                targetByOrigin[origin] == nil
            else { continue }
            targetByOrigin[origin] = entry.target
        }
        let work = claimFaviconOrigins(Set(targetByOrigin.keys))
            .compactMap { origin in targetByOrigin[origin].map { (origin, $0) } }
        guard !work.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            var anyStored = false
            for (origin, target) in work {
                defer { self.releaseFaviconOrigin(origin) }
                guard let url = URL(string: target) else { continue }
                if let png = await capability.fetchFavicon(for: url) {
                    if cache.store(png: png, forTarget: target) { anyStored = true }
                } else {
                    cache.recordMiss(forTarget: target)
                }
            }
            if anyStored { self.emitFaviconRefresh() }
        }
    }

    /// Marks the given origins in flight and returns those not already fetching.
    private func claimFaviconOrigins(_ origins: Set<String>) -> [String] {
        faviconLock.lock(); defer { faviconLock.unlock() }
        let fresh = origins.subtracting(faviconInFlightOrigins)
        faviconInFlightOrigins.formUnion(fresh)
        return Array(fresh)
    }

    private func releaseFaviconOrigin(_ origin: String) {
        faviconLock.lock(); defer { faviconLock.unlock() }
        faviconInFlightOrigins.remove(origin)
    }

    /// Re-emits the active mode's `mode.quickapps.changed` (unchanged pins) so its
    /// tiles re-read `listUrls` and pick up newly cached favicons. Other modes pick
    /// theirs up on next view — `listUrls` reads the now-warm cache.
    private func emitFaviconRefresh() {
        let state = composeBootstrapState()
        let activeID = bootstrapModeID()
        guard let mode = state.modes.first(where: { $0.id == activeID }) ?? state.modes.first else { return }
        emit(BridgeEventFactory.quickAppsChangedEvent(
            modeId: mode.id, quickApps: mode.quickApps,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// The recent-activity read surface. A fresh session has no activity; the durable
    /// DB-backed history read is a follow-on increment, so this returns the honest
    /// empty envelope (the dashboard renders an empty feed rather than fabricated rows).
    private func getRecentActivity(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: RecentActivityEnvelope())
    }

    private func decideConfirmation(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: DecideConfirmationInput = decodePayload(request), !input.id.isEmpty else {
            return invalidInput(request, "decideConfirmation requires an id and decision.")
        }
        guard let token = takeToken(id: input.id) else {
            return errorResponse(
                request, category: .invalidInput,
                code: "unknown_confirmation", message: "No pending confirmation for \(input.id)."
            )
        }
        // Only approve/cancel cross the bridge; anything else fails closed as cancel.
        let decision: ConfirmationDecision = (input.decision == "approve") ? .approve : .cancel
        _ = await runtime.decide(token: token, decision: decision)
        // Clear the active confirmation in the UI; the command's own completion/cancel
        // is carried by the lifecycle event stream.
        emit(BridgeEventFactory.confirmationEvent(disclosure: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()))
        return ok(request, payload: DecideConfirmationResult(confirmationId: input.id, decision: input.decision))
    }

    /// Validates a settings patch against the deterministic allowlist (ADR-003) and
    /// persists an accepted patch through the settings store: unknown or
    /// policy-weakening keys are rejected before anything is saved, and a store
    /// failure is a structured error — `accepted` is never reported for a patch
    /// that did not become durable (FR-CFG-04).
    private func updateSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard
            let data = try? JSONEncoder().encode(request.payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let patch = object["patch"] as? [String: Any]
        else {
            return invalidInput(request, "updateSettings requires a patch.")
        }
        let changes = (patch["changes"] as? [String: Any]) ?? [:]
        let errors = SettingsPatchValidator.validate(changes: changes)
        guard errors.isEmpty else {
            return ok(request, payload: UpdateSettingsResult(accepted: false))
        }
        let settingsChanges = SettingsChanges(validatedChanges: changes)
        if let settingsStore {
            do {
                try settingsStore.apply(settingsChanges)
            } catch {
                return errorResponse(
                    request, category: .internalFailure,
                    code: "settings_not_saved",
                    message: "The settings change could not be saved."
                )
            }
            // Live policy re-arm (NIC-137): a change to "Ask before all actions" takes
            // effect immediately for the next command, not just on next launch.
            if let confirmAll = settingsChanges.confirmAllActions {
                runtime.updateConfirmAllActions(confirmAll)
            }
            // Let a settings-driven producer re-sample now (NIC-128): the Stocks producer
            // refreshes when the ticker list changes, so an edit is live at once rather than
            // on its next slow tick.
            onSettingsChanged?(settingsChanges)
            // Live cross-webview sync: every surface (dashboard + the separate native
            // settings window) reflects the new assistant name, mode colors, and motion
            // preference immediately, not just on next launch.
            emit(BridgeEventFactory.settingsChangedEvent(
                snapshot: resolvedSettingsSnapshot(),
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
        }
        return ok(request, payload: UpdateSettingsResult(accepted: true))
    }

    /// Reads the durable settings on demand so the settings UI initializes its
    /// controls from persisted state rather than hardcoded defaults (NIC-141). This
    /// is the read side of `updateSettings`; effective defaults are resolved in one
    /// deterministic place (``EffectiveSettings``).
    ///
    /// It never errors: a store load failure or a workspace-less host with no store
    /// bound (some tests) yields the effective defaults, mirroring how bootstrap
    /// degrades a missing stored default to the configured default mode. The
    /// configured default mode id is read through the same layered/shipped config
    /// path bootstrap uses — the "default mode" setting, distinct from the currently
    /// active mode.
    private func getSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: resolvedSettingsSnapshot())
    }

    /// The effective settings snapshot — the single resolution shared by `getSettings`
    /// (the read) and the `settings.changed` event (live sync after a write).
    private func resolvedSettingsSnapshot() -> CerebralHelmSettingsSnapshot {
        let stored = (try? settingsStore?.load()).flatMap { $0 } ?? StoredSettings()
        let configDefaultModeID: String?
        if let workspace {
            configDefaultModeID = BootstrapComposer.defaultModeID(workspace: workspace)
        } else {
            configDefaultModeID = BootstrapComposer.defaultModeID(configDirectory: configDirectory)
        }
        return EffectiveSettings.resolve(stored: stored, configDefaultModeID: configDefaultModeID)
    }

    /// The bootstrap state with mode restore applied (FR-MOD-05). This is the
    /// single composition every surface must use — the `getBootstrapState`
    /// operation and the shell's synchronous `window.__cerebralBootstrap`
    /// injection — so a restored mode can never differ by transport.
    public func composeBootstrapState() -> CerebralHelmBridgeBootstrapState {
        composeState(activeModeID: bootstrapModeID())
    }

    /// The mode bootstrap should activate: the last active mode when it still
    /// exists in config (FR-MOD-05 restart restore), else the stored default
    /// mode, else `nil` for the configured default. Stale references fall back,
    /// never error.
    private func bootstrapModeID() -> String? {
        if let store = modeStateStore,
           let lastActive = try? store.loadActiveModeID(),
           BootstrapComposer.modeExists(lastActive, configDirectory: configDirectory) {
            return lastActive
        }
        guard
            let store = settingsStore,
            let settings = try? store.load(),
            let stored = settings.defaultModeID,
            BootstrapComposer.modeExists(stored, configDirectory: configDirectory)
        else { return nil }
        return stored
    }

    // MARK: - Confirmation flow

    /// When a command pauses for confirmation, remember its single-use token and push
    /// the policy-owned disclosure to the dashboard as a `confirmation.changed` event.
    private func registerAwaitingConfirmation(_ outcome: CommandRuntimeOutcome) {
        guard case let .awaitingConfirmation(_, disclosure, token) = outcome else { return }
        tokenLock.lock()
        pendingTokens[token.confirmationID] = token
        tokenLock.unlock()
        emit(BridgeEventFactory.confirmationEvent(
            disclosure: disclosure, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func takeToken(id: String) -> ConfirmationToken? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return pendingTokens.removeValue(forKey: id)
    }

    private func emit(_ event: CerebralHelmBridgeEvent) {
        guard let data = try? BridgeMessageCoding.encoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        emitEventJSON(json)
    }

    // MARK: - Payload mapping

    private struct SubmitCommandInput: Decodable {
        let rawInput: String
        let source: String?
    }
    private struct SuggestCommandsInput: Decodable {
        let query: String
        let limit: Int?
    }
    private struct CommandSuggestionDTO: Encodable {
        let command: String
        let label: String
        let detail: String?
        let kind: String
        let requiresArgument: Bool
        let available: Bool
        let unavailableReason: String?
    }
    private struct SuggestCommandsResult: Encodable {
        let suggestions: [CommandSuggestionDTO]
    }
    private struct CommandReceipt: Encodable {
        let commandId: String
        let accepted: Bool
    }
    private struct ApplyModeInput: Decodable {
        let modeId: String
    }
    private struct ApplyModeResult: Encodable {
        let modeId: String
        let status: String
    }
    private struct CaptureNoteInput: Decodable {
        let title: String
        let body: String
        let kind: String?
    }
    private struct CaptureNoteResult: Encodable {
        let noteId: String
    }
    private struct SearchNotesInput: Decodable {
        let text: String
        let limit: Int?
    }
    /// `listNotes` input (NIC-162): how many of the most recently changed notes to
    /// return. The reported total is unaffected by it.
    private struct ListNotesInput: Decodable {
        let limit: Int?
    }
    /// The library wire shape (NIC-162). `available` is false when the knowledge root could not be
    /// read at all — the card then says so instead of showing an empty library.
    private struct NoteListItemDTO: Encodable {
        let path: String
        let title: String
        let folder: String
        let updated: String?
    }
    private struct ListNotesResult: Encodable {
        let available: Bool
        let root: String
        /// Every note under the root, regardless of the requested limit.
        let total: Int
        let notes: [NoteListItemDTO]

        init(_ output: CerebralHelmNoteListOutput) {
            available = true
            root = output.root
            total = output.total
            notes = output.notes.map {
                NoteListItemDTO(path: $0.path, title: $0.title, folder: $0.folder, updated: $0.updated)
            }
        }

        private init() {
            available = false
            root = ""
            total = 0
            notes = []
        }

        static let unavailable = ListNotesResult()
    }
    /// `listCourses` input (quick actions phase 5): how many courses to return, most recently
    /// written first.
    /// The receipt for starting a run (quick actions phase 5). It deliberately carries no results:
    /// they arrive as events, and a payload that looked like results would invite a caller to read
    /// the first snapshot as the answer.
    private struct ListUnreadMailInput: Decodable {
        let limit: Int?
    }
    /// **`MailMessage.preview` is deliberately absent here.** The message previews the daily brief
    /// composes from stay host-side: the composer runs in Swift, so nothing needs them in the web
    /// layer, and a field that never crosses cannot be rendered, logged by a browser, or read out
    /// of a devtools tree. Adding it is a decision to be taken deliberately, not a mapping to be
    /// completed for symmetry.
    private struct UnreadMailItemDTO: Encodable {
        let id: String
        let byline: String
        let subject: String
        let receivedAt: String?
        /// The RFC 5322 Message-ID — the handle `mail.open` takes. Absent when the sender omitted
        /// one, in which case the row renders as text rather than a link.
        let messageId: String?
    }
    /// The unread messages, or an honest reason there are none to show. `state` distinguishes
    /// "your inbox is clear" from "we could not look", which an empty array alone cannot.
    private struct UnreadMailResult: Encodable {
        let state: String
        let messages: [UnreadMailItemDTO]
        let reason: String?

        init(_ messages: [MailMessage]) {
            state = "ready"
            reason = nil
            self.messages = messages.map {
                UnreadMailItemDTO(
                    id: $0.id, byline: $0.byline, subject: $0.subject,
                    receivedAt: $0.receivedAt, messageId: $0.rfc822MessageID
                )
            }
        }

        private init(state: String, reason: String?) {
            self.state = state
            self.reason = reason
            self.messages = []
        }

        static func unavailable(state: String, reason: String?) -> UnreadMailResult {
            UnreadMailResult(state: state, reason: reason)
        }
    }
    private struct ConnectGmailInput: Decodable {
        let disconnect: Bool?
    }
    /// The outcome of connecting. `canRefresh` false means the grant cannot renew itself and the
    /// surface must say so — it is not a successful connection.
    private struct ConnectGmailResult: Encodable {
        let connected: Bool
        let scope: String?
        let canRefresh: Bool
    }
    private struct ComposeReportInput: Decodable {
        let reportID: String
        enum CodingKeys: String, CodingKey { case reportID = "reportId" }
    }

    /// The answer to *starting* a composition — not to finishing one.
    ///
    /// The document arrives as `report.composition.changed` events, so this says only whether the
    /// work began. `state` still distinguishes "no model here" from "under way", because a surface
    /// that got neither a document nor a reason would have nothing to render.
    private struct ComposeReportResult: Encodable {
        let state: String
        let reason: String?

        static let started = ComposeReportResult(state: "composing", reason: nil)

        static func unavailable(_ reason: String) -> ComposeReportResult {
            ComposeReportResult(state: "unavailable", reason: reason)
        }
    }

    /// Records when the first block arrived, once.
    ///
    /// A lock rather than an actor, and that is the point rather than a preference: the progress
    /// callback is synchronous, so an actor would have to be marked from a detached `Task` — which
    /// is not guaranteed to have run by the time the terminal emission reads it. That race left
    /// `firstBlockMs` nil under parallel load, which is exactly the shape of bug that reaches
    /// production reported as "sometimes the timing is missing".
    ///
    /// Time-to-first-block is kept apart from the total deliberately: they answer different
    /// questions, and the first is what decides whether nine seconds reads as arrival or as a stall.
    private final class FirstBlockClock: @unchecked Sendable {
        private let lock = NSLock()
        private var at: Date?

        func markIfUnset(_ date: Date) {
            lock.lock(); defer { lock.unlock() }
            if at == nil { at = date }
        }

        func milliseconds(since start: Date) -> Int? {
            lock.lock(); defer { lock.unlock() }
            return at.map { Int($0.timeIntervalSince(start) * 1000) }
        }
    }

    private struct SystemChecksResult: Encodable {
        let started: Bool
        let checkCount: Int

        static let unavailable = SystemChecksResult(started: false, checkCount: 0)
    }
    private struct ListCoursesInput: Decodable {
        let limit: Int?
    }
    private struct CourseFolderDTO: Encodable {
        let course: String
        /// Root-relative, so the picker can compare it directly to a note listing's folder and
        /// filter that course's notes without a second read.
        let folder: String
        let noteCount: Int
        let updated: String?
    }
    /// The course notebooks on disk (quick actions phase 5). `available` is false when the
    /// knowledge root could not be read at all — "no courses yet" and "your vault is gone" must
    /// never look the same, the same distinction ``ListNotesResult`` draws.
    private struct ListCoursesResult: Encodable {
        let available: Bool
        /// The root-relative school folder the courses came from.
        let root: String
        let courses: [CourseFolderDTO]

        init(_ output: CerebralHelmCourseListOutput) {
            available = true
            root = output.courseRoot
            courses = output.courses.map {
                CourseFolderDTO(
                    course: $0.courseName, folder: $0.courseFolder,
                    noteCount: $0.courseNoteCount, updated: $0.courseUpdated
                )
            }
        }

        private init() {
            available = false
            root = ""
            courses = []
        }

        static let unavailable = ListCoursesResult()
    }
    private struct CreateCourseNoteInput: Decodable {
        let course: String
        let title: String
    }
    /// The created note (quick actions phase 5). `path` is the same handle `note.open` takes, so
    /// the picker can open what it just created — except while `awaitingConfirmation`, where
    /// nothing has been written yet and there is no path to offer.
    private struct CreateCourseNoteResult: Encodable {
        let course: String
        let path: String
        let title: String
        /// False when a note of that title already existed for that day and was returned rather
        /// than overwritten.
        let created: Bool
        let awaitingConfirmation: Bool
    }
    private struct NoteHit: Encodable {
        let noteId: String
        let title: String
        let excerpt: String
        /// The note's root-relative path (quick actions phase 5) — the identity the
        /// `search-notes` picker merges on and the handle it opens by. It is the one
        /// key both note sources agree on: a note authored outside CerebralHelm has
        /// no frontmatter id, so `noteId` cannot address the whole library. Relative
        /// by construction; an absolute path never crosses this boundary.
        let path: String
    }
    private struct SearchNotesResult: Encodable {
        let results: [NoteHit]
    }
    private struct DecideConfirmationInput: Decodable {
        let id: String
        let decision: String
    }
    private struct DecideConfirmationResult: Encodable {
        let confirmationId: String
        let decision: String
    }
    private struct UpdateSettingsResult: Encodable {
        let accepted: Bool
    }
    private struct DiscoveredApp: Encodable {
        let bundleId: String
        let name: String
        let iconPng: String?
        /// The configured app reference this bundle id backs (nil = not pinnable).
        let referenceId: String?
    }
    private struct ListAppsResult: Encodable {
        let apps: [DiscoveredApp]
        let truncated: Bool
    }
    private struct SpeedTestResult: Encodable {
        /// "ok" | "partial" | "unavailable" (mirrors the tool output).
        let status: String
        let downloadMbps: Double?
        let uploadMbps: Double?
        let testedAt: String?
    }
    private struct UpdateQuickAppsInput: Decodable {
        let modeId: String
        let quickApps: [String]
    }
    /// `{ reference, value }` — the `storeSecret` payload (NIC-134). `value` is the live secret;
    /// it is written to the Keychain and never echoed back or logged.
    private struct StoreSecretInput: Decodable {
        let reference: String
        let value: String
    }
    private struct StoreSecretResult: Encodable {
        let reference: String
        let stored: Bool
    }
    private struct SecretStatusInput: Decodable {
        let reference: String
    }
    /// Presence only — whether the reference is bound. Never carries the value (FR-CFG-03).
    private struct SecretStatusResult: Encodable {
        let reference: String
        let bound: Bool
    }
    /// `{ reference, deleted }` — the `deleteSecret` result (NIC-133). `deleted` is false when the
    /// reference was already absent (an idempotent no-op), true when a stored value was removed.
    private struct DeleteSecretResult: Encodable {
        let reference: String
        let deleted: Bool
    }
    /// `{ connected, scope? }` — the `connectSpotify` result (NIC-133). Reports success and the
    /// granted scope only; the OAuth tokens never cross the bridge (they live in the Keychain).
    private struct ConnectSpotifyResult: Encodable {
        let connected: Bool
        let scope: String?
    }
    private struct OpenLayoutInput: Decodable {
        let modeId: String
    }
    private struct OpenLayoutResult: Encodable {
        let accepted: Bool
        let modeId: String
    }
    private struct CloseLayoutResult: Encodable {
        let closed: Bool
    }
    private struct ToggleLayoutInput: Decodable {
        let ref: String
    }
    private struct ToggleLayoutResult: Encodable {
        let accepted: Bool
    }
    private struct PinLayoutWindowInput: Decodable {
        let modeId: String
        let ref: String
    }
    private struct PinLayoutWindowResult: Encodable {
        let accepted: Bool
        let errors: [String]
    }
    private struct AddLayoutTargetInput: Decodable {
        let ref: String
    }
    private struct AddLayoutTargetResult: Encodable {
        let accepted: Bool
    }
    private struct ToggleModeCollapseInput: Decodable {
        let modeId: String
    }
    private struct ToggleModeCollapseResult: Encodable {
        let collapsed: Bool
    }
    private struct WindowRefInput: Decodable {
        let windowId: String
    }
    private struct WindowActionResult: Encodable {
        let ok: Bool
    }
    private struct WindowDTO: Encodable {
        let id: String
        let title: String
        let minimized: Bool
    }
    private struct WindowGroupDTO: Encodable {
        let bundleId: String
        let appName: String
        let appIconPng: String?
        let windows: [WindowDTO]
    }
    private struct WindowInventory: Encodable {
        let apps: [WindowGroupDTO]
    }
    private struct UpdateLayoutInput: Decodable {
        let modeId: String
        let layout: [String: JSONAny]
    }
    private struct UpdateLayoutResult: Encodable {
        let accepted: Bool
        let errors: [String]
    }
    private struct CaptureWindow: Encodable {
        let ref: String
        let kind: String
        let frame: String
    }
    private struct CaptureLayoutResult: Encodable {
        let windows: [CaptureWindow]
    }
    private struct UpdateQuickAppsResult: Encodable {
        let accepted: Bool
        let quickApps: [String]
        let errors: [String]
    }
    private struct AddUrlReferenceInput: Decodable {
        let url: String
        let label: String?
        /// Optional Google Chrome profile directory (`--profile-directory`, NIC-151);
        /// when present the minted URL opens in that Chrome profile.
        let profile: String?
    }
    /// A configured URL reference, as delivered to the dashboard (NIC-146). `iconPng`
    /// is the site's cached favicon as base64 PNG (NIC-147), omitted when none is
    /// cached yet — the tile shows its placeholder glyph and upgrades live once the
    /// background fetch lands (`encodeIfPresent` drops the nil, mirroring app icons).
    private struct UrlReferenceDTO: Encodable {
        let id: String
        let label: String
        let target: String
        let iconPng: String?
        /// The reference's Chrome profile, when one is configured (NIC-151);
        /// `encodeIfPresent` omits it otherwise, so profile-less tiles are unchanged.
        let profile: String?
    }
    private struct AddUrlReferenceResult: Encodable {
        let accepted: Bool
        /// The minted (or already-existing) reference when accepted; nil on rejection.
        let reference: UrlReferenceDTO?
        let errors: [String]
    }
    private struct ListUrlsResult: Encodable {
        let urls: [UrlReferenceDTO]
    }
    /// A Chrome profile for the dropdown + avatar badges (NIC-151). `directory` is the
    /// `--profile-directory` value; `iconPng` is the account avatar, omitted when none.
    private struct ChromeProfileDTO: Encodable {
        let directory: String
        let name: String
        let iconPng: String?
    }
    private struct CalendarDTO: Encodable {
        let id: String
        let title: String
        let colorHex: String?
    }
    /// The `create-event` form's collected values. `calendarTitle` is carried alongside the id
    /// purely so a confirmation disclosure can name the calendar in words — the id alone would be
    /// unreadable in a prompt.
    private struct MessageRecipientsResult: Encodable {
        struct Recipient: Encodable {
            let id: String
            let name: String
            let kind: String
            let groupSize: Int?
            let handle: String?

            init(_ recipient: MessageRecipient) {
                id = recipient.id
                name = recipient.name
                kind = recipient.kind
                groupSize = recipient.groupSize
                handle = recipient.handle
            }
        }

        let recipients: [Recipient]
        let available: Bool
        let reason: String?
    }

    private struct SendMessageInput: Decodable {
        let body: String
        let target: String
        let targetKind: String
        let targetName: String?
        let groupSize: Int?
    }

    private struct SendMessageResult: Encodable {
        let targetName: String
        let sent: Bool
        /// True on the normal path — this action always confirms.
        let awaitingConfirmation: Bool
    }

    private struct SportsEventsResult: Encodable {
        struct Competitor: Encodable {
            let abbreviation: String
            let name: String
            let score: String
            let color: String?
            let isHome: Bool
            let record: String?
        }

        struct LeaderboardEntry: Encodable {
            let order: Int
            let position: String?
            let name: String
            let score: String
            let thru: String?
        }

        struct Event: Encodable {
            let id: String
            let league: String
            let name: String
            let shortName: String
            let state: String
            let detail: String
            let venue: String?
            let competitors: [Competitor]
            let leaderboard: [LeaderboardEntry]

            init(_ event: SportsEvent) {
                id = event.id
                league = event.league
                name = event.name
                shortName = event.shortName
                state = event.state.rawValue
                detail = event.detail
                venue = event.venue
                competitors = event.competitors.map {
                    Competitor(
                        abbreviation: $0.abbreviation, name: $0.name, score: $0.score,
                        color: $0.color, isHome: $0.isHome, record: $0.record
                    )
                }
                leaderboard = event.leaderboard.map {
                    LeaderboardEntry(
                        order: $0.order, position: $0.position, name: $0.name,
                        score: $0.score, thru: $0.thru
                    )
                }
            }
        }

        let events: [Event]
        /// False on a host with no sports provider at all — different from "nothing is on today".
        let available: Bool
        /// Present when the read failed, so the picker says so rather than showing an empty list.
        let reason: String?
    }

    private struct LinearOptionsResult: Encodable {
        struct Option: Encodable {
            let id: String
            let name: String
        }

        struct Team: Encodable {
            let id: String
            let key: String
            let name: String
            let projects: [Option]
            let labels: [Option]

            init(_ team: LinearWorkspaceInfo.Team) {
                id = team.id
                key = team.key
                name = team.name
                projects = team.projects.map { Option(id: $0.id, name: $0.name) }
                labels = team.labels.map { Option(id: $0.id, name: $0.name) }
            }
        }

        let teams: [Team]
        /// False on a host with no Linear client at all — a different fact from an empty workspace.
        let available: Bool
        /// Present when the workspace could not be read, so the form can say so rather than
        /// rendering empty dropdowns that look like the user has no teams.
        let reason: String?
    }

    private struct LinearProjectCycleInput: Decodable {
        let project: String
    }

    private struct LinearProjectCycleResult: Encodable {
        struct State: Encodable {
            let name: String
            let type: String
            let color: String
            let position: Double
        }

        struct Issue: Encodable {
            let identifier: String
            let title: String
            let url: String
            let priority: Int
            let estimate: Int?
            let sortOrder: Double
            let state: State
            let labels: [String]
            let assignee: String?
            let assigneeInitials: String?

            enum CodingKeys: String, CodingKey {
                case identifier, title, url, priority, estimate, sortOrder
                case state, labels, assignee, assigneeInitials
            }

            /// Explicit nulls, for the reason given on the enclosing type.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(identifier, forKey: .identifier)
                try container.encode(title, forKey: .title)
                try container.encode(url, forKey: .url)
                try container.encode(priority, forKey: .priority)
                try container.encode(estimate, forKey: .estimate)
                try container.encode(sortOrder, forKey: .sortOrder)
                try container.encode(state, forKey: .state)
                try container.encode(labels, forKey: .labels)
                try container.encode(assignee, forKey: .assignee)
                try container.encode(assigneeInitials, forKey: .assigneeInitials)
            }

            init(_ issue: LinearProjectCycleInfo.Issue) {
                identifier = issue.identifier
                title = issue.title
                url = issue.url
                priority = issue.priority
                estimate = issue.estimate
                sortOrder = issue.sortOrder
                state = State(
                    name: issue.state.name, type: issue.state.type,
                    color: issue.state.color, position: issue.state.position
                )
                labels = issue.labels
                assignee = issue.assignee
                assigneeInitials = issue.assigneeInitials
            }
        }

        struct Cycle: Encodable {
            let id: String
            let number: Int
            let name: String?
            let startsAt: String
            let endsAt: String

            enum CodingKeys: String, CodingKey { case id, number, name, startsAt, endsAt }

            /// Explicit nulls, for the reason given on the enclosing type — a cycle is usually
            /// unnamed, so `name` is the common case rather than the rare one.
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(number, forKey: .number)
                try container.encode(name, forKey: .name)
                try container.encode(startsAt, forKey: .startsAt)
                try container.encode(endsAt, forKey: .endsAt)
            }

            init(_ cycle: LinearProjectCycleInfo.Cycle) {
                id = cycle.id
                number = cycle.number
                name = cycle.name
                startsAt = cycle.startsAt
                endsAt = cycle.endsAt
            }
        }

        /// `nil` when the descriptor's `linear_project` matches no Linear project. Distinct from an
        /// empty `issues`, which means the project matched and has nothing in the cycle.
        let matchedProject: String?
        let matchedProjectURL: String?
        let cycle: Cycle?
        let issues: [Issue]
        /// True when Linear had more issues than one page returned, so a cut list can say so.
        let truncated: Bool
        /// False on a host with no Linear client at all — a different fact from an empty cycle.
        let available: Bool
        /// Present when the read was attempted and failed.
        let reason: String?

        init(_ info: LinearProjectCycleInfo) {
            matchedProject = info.matchedProject
            matchedProjectURL = info.matchedProjectURL
            cycle = info.cycle.map(Cycle.init)
            issues = info.issues.map(Issue.init)
            truncated = info.truncated
            available = true
            reason = nil
        }

        private init(available: Bool, reason: String?) {
            matchedProject = nil
            matchedProjectURL = nil
            cycle = nil
            issues = []
            truncated = false
            self.available = available
            self.reason = reason
        }

        static let unavailable = LinearProjectCycleResult(available: false, reason: nil)
        static func failed(reason: String) -> LinearProjectCycleResult {
            LinearProjectCycleResult(available: true, reason: reason)
        }

        // Encoded by hand so that a nil optional lands on the wire as an explicit `null` rather
        // than as an ABSENT KEY, which is what Swift's synthesized `Codable` does (it uses
        // `encodeIfPresent`). The difference is not cosmetic: the web layer declares these as
        // `T | null`, and a `matchedProject === null` check — the one that separates a broken
        // link from a quiet cycle — is silently false against `undefined`. Keeping the wire
        // faithful to the declared type means the surface cannot be wrong about which state it
        // is in.
        enum CodingKeys: String, CodingKey {
            case matchedProject
            // Swift spells it `URL`, JSON spells it `Url`. Mapped explicitly rather than renaming
            // either side, and pinned by a test — a silent case mismatch here is a field the web
            // layer reads as `undefined` forever.
            case matchedProjectURL = "matchedProjectUrl"
            case cycle, issues, truncated, available, reason
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(matchedProject, forKey: .matchedProject)
            try container.encode(matchedProjectURL, forKey: .matchedProjectURL)
            try container.encode(cycle, forKey: .cycle)
            try container.encode(issues, forKey: .issues)
            try container.encode(truncated, forKey: .truncated)
            try container.encode(available, forKey: .available)
            try container.encode(reason, forKey: .reason)
        }
    }

    private struct ScaffoldProjectInput: Decodable {
        let name: String
        let location: String?
        let summary: String?
        let importance: Int?
    }

    private struct ScaffoldProjectResult: Encodable {
        /// The created folder's path, or — when the action gated — the pending command id.
        let projectPath: String
        let awaitingConfirmation: Bool
    }

    private struct CreateSpotifyPlaylistInput: Decodable {
        let name: String
        let description: String?
        let isPublic: Bool?
    }

    private struct CreateSpotifyPlaylistResult: Encodable {
        /// The playlist id, or — when the action gated — the pending command id.
        let playlistId: String
        let name: String
        let url: String?
        /// Whether Spotify came forward at the new playlist — best-effort, never a failure.
        let opened: Bool
        let awaitingConfirmation: Bool
        /// Reserved for the ok-path shape; the reconnect case is an error response.
        let needsReconnect: Bool
    }

    private struct CreateLinearIssueInput: Decodable {
        let title: String
        let description: String?
        let teamId: String
        let teamName: String?
        let projectId: String?
        let projectName: String?
        let labelIds: [String]?
        let labelNames: [String]?
        let priority: Int?
    }

    private struct CreateLinearIssueResult: Encodable {
        /// The issue identifier (`NIC-176`), or — when the action gated — the command id whose
        /// confirmation is pending. `awaitingConfirmation` says which.
        let identifier: String
        let url: String?
        let awaitingConfirmation: Bool
    }

    private struct FolderSelectionResult: Encodable {
        let folderPath: String?
        let relativeFolder: String?
        let cancelled: Bool
        let outsideRoot: Bool
        /// False on a host with no picker at all, so the form can fall back to typing rather than
        /// showing a button that silently does nothing.
        let available: Bool
    }

    private struct CloneRepositoryInput: Decodable {
        let repositoryUrl: String
        let directory: String?
    }

    private struct CloneRepositoryResult: Encodable {
        /// The path the repository was cloned to, or — when the action gated — the command id whose
        /// confirmation is now pending. `awaitingConfirmation` says which, so a caller never
        /// reports "cloned" for something still waiting on the user.
        let clonedPath: String
        let repositoryName: String
        let awaitingConfirmation: Bool
    }

    private struct CreateCalendarEventInput: Decodable {
        let title: String
        let startsAt: String
        let endsAt: String
        let calendarId: String?
        let calendarTitle: String?
        let location: String?
        let notes: String?
    }

    private struct CreateCalendarEventResult: Encodable {
        /// The created event's id, or — when the action gated — the command id whose confirmation
        /// is now pending. `awaitingConfirmation` says which, so a caller never reports "created"
        /// for something still waiting on the user.
        let eventId: String
        let calendarTitle: String?
        let awaitingConfirmation: Bool
    }

    private struct CalendarsResult: Encodable {
        /// Whether Calendar access is granted; false → the UI shows "grant Calendar access".
        let authorized: Bool
        let calendars: [CalendarDTO]
    }
    /// The knowledge-rebuild wire shape (NIC-163). `rebuilt` is false only when the host has no
    /// knowledge composition (pre-Mac/tests) — the UI then shows the surface as unavailable rather
    /// than reporting a rebuild that never ran. Otherwise it carries the root that was read and how
    /// many notes were indexed, so the panel can say what the rebuild actually covered.
    private struct KnowledgeRebuildResult: Encodable {
        let rebuilt: Bool
        let root: String
        let noteCount: Int

        init(_ info: KnowledgeRebuildInfo) {
            rebuilt = true
            root = info.root
            noteCount = info.noteCount
        }

        private init() {
            rebuilt = false
            root = ""
            noteCount = 0
        }

        static let unavailable = KnowledgeRebuildResult()
    }

    /// The Canvas ingest status wire shape (NIC-132). `available` is false only when the host has no
    /// ingest store (pre-Mac/tests) — the UI then shows "requires the macOS host". Otherwise it
    /// carries the pairing endpoint/token and the last scrape's age/counts.
    private struct CanvasStatusItemDTO: Encodable {
        let id: String
        let label: String
        let hidden: Bool
    }
    private struct CanvasStatusResult: Encodable {
        let available: Bool
        let endpoint: String
        let token: String?
        let lastScrapedAt: String?
        let courseCount: Int
        let deadlineCount: Int
        let courses: [CanvasStatusItemDTO]
        let deadlines: [CanvasStatusItemDTO]

        init(_ info: CanvasStatusInfo) {
            available = true
            endpoint = info.endpoint
            token = info.token
            lastScrapedAt = info.lastScrapedAt
            courseCount = info.courseCount
            deadlineCount = info.deadlineCount
            courses = info.courses.map { CanvasStatusItemDTO(id: $0.id, label: $0.label, hidden: $0.hidden) }
            deadlines = info.deadlines.map { CanvasStatusItemDTO(id: $0.id, label: $0.label, hidden: $0.hidden) }
        }

        private init() {
            available = false
            endpoint = ""
            token = nil
            lastScrapedAt = nil
            courseCount = 0
            deadlineCount = 0
            courses = []
            deadlines = []
        }

        static let unavailable = CanvasStatusResult()
    }
    private struct SetCanvasHiddenInput: Decodable {
        let id: String
        let hidden: Bool
    }
    private struct ChromeProfilesResult: Encodable {
        let profiles: [ChromeProfileDTO]
        /// The user's pinned Chrome-profile app references, so a pinned tile resolves
        /// its label + profile (and thence its avatar) without a separate feed.
        let references: [AppReferenceDTO]
    }
    private struct AddChromeProfileInput: Decodable {
        let directory: String
        let name: String?
    }
    /// A configured app reference (NIC-151): mirrors `UrlReferenceDTO` but for an app
    /// target (a bundle id). `profile` is the Chrome profile it opens in, when set.
    private struct AppReferenceDTO: Encodable {
        let id: String
        let label: String
        let target: String
        let profile: String?
    }
    private struct AddChromeProfileResult: Encodable {
        let accepted: Bool
        let reference: AppReferenceDTO?
        let errors: [String]
    }
    /// Mirrors the bridge `getRecentActivity` payload wrapper `{ recentActivity: … }`.
    private struct RecentActivityEnvelope: Encodable {
        let recentActivity = Activity()
        struct Activity: Encodable {
            let commands: [String] = []
            let toolCalls: [String] = []
            let confirmations: [String] = []
            let modeSessions: [String] = []
            let errors: [String] = []
        }
    }

    private func receipt(for outcome: CommandRuntimeOutcome) -> CommandReceipt {
        switch outcome {
        case let .completed(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case let .awaitingConfirmation(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case .rejected:
            return CommandReceipt(commandId: "", accepted: false)
        }
    }

    private func decodePayload<T: Decodable>(_ request: CerebralHelmBridgeOperationRequest) -> T? {
        guard let data = try? JSONEncoder().encode(request.payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodePayload<T: Encodable>(_ value: T) -> [String: JSONAny] {
        guard
            let data = try? JSONEncoder().encode(value),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }

    // MARK: - Responses

    private func ok<T: Encodable>(
        _ request: CerebralHelmBridgeOperationRequest, payload: T
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: nil,
            messageID: request.messageID,
            operation: request.operation,
            payload: encodePayload(payload),
            schemaVersion: messageSchemaVersion,
            status: .ok,
            type: .bridgeOperationResponse
        )
    }

    private func errorResponse(
        _ request: CerebralHelmBridgeOperationRequest,
        category: CerebralContracts.Category,
        code: String,
        message: String
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: CerebralHelmBridgeOperationResponseError(
                category: category, code: code, details: nil, message: message, remediation: nil
            ),
            messageID: request.messageID,
            operation: request.operation,
            payload: [:],
            schemaVersion: messageSchemaVersion,
            status: .error,
            type: .bridgeOperationResponse
        )
    }

    private func invalidInput(
        _ request: CerebralHelmBridgeOperationRequest, _ message: String
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(request, category: .invalidInput, code: "bridge_invalid_input", message: message)
    }

    private func unimplemented(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(
            request,
            category: .unavailableCapability,
            code: "bridge_operation_unimplemented",
            message: "This bridge operation is not wired to the runtime yet."
        )
    }
}

/// What the host reports back from a Gmail connect (Gmail integration).
///
/// Carried as a plain value rather than the adapter's own type so `BridgeSession` stays free of
/// AppKit — the same seam every other host-injected closure uses.
public struct GmailConnectionInfo: Sendable, Equatable {
    public let scope: String?
    /// False means the grant cannot renew itself. Reported, never smoothed over.
    public let canRefresh: Bool

    public init(scope: String?, canRefresh: Bool) {
        self.scope = scope
        self.canRefresh = canRefresh
    }
}

/// A connect failure the surface can act on, mapped by the host from its adapter's error.
///
/// The three cases have three different remedies, and collapsing them into "connect failed" would
/// send the user looking in the wrong place: enter a Client ID, press Connect again, or nothing at
/// all because they simply closed the browser.
public struct GmailConnectError: Error, Sendable {
    public let category: CerebralContracts.Category
    public let code: String
    public let message: String

    public init(category: CerebralContracts.Category, code: String, message: String) {
        self.category = category
        self.code = code
        self.message = message
    }

    public static let clientIDMissing = GmailConnectError(
        category: .invalidInput, code: "gmail_client_id_missing",
        message: "Add your Google Client ID in Settings → Setup, then connect."
    )
    public static let cancelled = GmailConnectError(
        category: .invalidInput, code: "gmail_connect_cancelled",
        message: "Gmail wasn’t connected — the browser was closed or consent was declined."
    )
    public static func failed(_ detail: String) -> GmailConnectError {
        GmailConnectError(category: .providerFailure, code: "gmail_connect_failed", message: detail)
    }
}
