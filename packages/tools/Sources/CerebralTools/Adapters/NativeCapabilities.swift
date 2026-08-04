import CerebralCore

/// Errors any native capability can raise.
///
/// Shared across every adapter so the executor (NIC-29) can map them to stable
/// error categories (FR-TOL-06) regardless of which platform capability failed.
public enum NativeCapabilityError: Error, Equatable, Sendable {
    /// The capability is not present in this runtime (FR-SHL-06).
    case unavailable
    /// The platform denied permission for the operation.
    case permissionDenied
    /// A required resource — e.g. a configured application — was not found.
    case notFound(String)
    /// The operation exceeded its deadline.
    case timedOut
    /// The operation was cancelled before completing.
    case cancelled
    /// An otherwise-unclassified provider failure.
    case adapterFailure(String)
}

// MARK: - app.open

public protocol AppCapability: Sendable {
    func open(appID: String) async throws -> AppOpenResult
}

public struct AppOpenResult: Equatable, Sendable {
    public let appID: String
    public let launched: Bool
    public let alreadyRunning: Bool

    public init(appID: String, launched: Bool, alreadyRunning: Bool) {
        self.appID = appID
        self.launched = launched
        self.alreadyRunning = alreadyRunning
    }
}

// MARK: - project.open

/// Opens a repository *directory* in the configured editor (NIC-131). Distinct from
/// ``AppCapability``, which launches a configured app reference by id and has no path
/// input by construction: this takes a filesystem path, so it is a separate, path-aware
/// capability. The adapter constrains the path to the configured projects root — a path
/// outside it is `NativeCapabilityError.permissionDenied` — so no arbitrary path can be
/// opened, and only the configured editor is ever launched.
public protocol ProjectCapability: Sendable {
    func open(repoPath: String) async throws -> ProjectOpenResult
}

public struct ProjectOpenResult: Equatable, Sendable {
    public let repoPath: String
    public let opened: Bool

    public init(repoPath: String, opened: Bool) {
        self.repoPath = repoPath
        self.opened = opened
    }
}

// MARK: - url.open

public protocol URLCapability: Sendable {
    func open(urlID: String) async throws -> URLOpenResult
}

public struct URLOpenResult: Equatable, Sendable {
    public let urlID: String
    public let opened: Bool
    public let resolvedURL: String
    /// Whether an existing browser tab CH had opened for this URL was surfaced
    /// (focused) instead of opening a new one (NIC-145). `false` for a fresh open.
    public let surfaced: Bool

    public init(urlID: String, opened: Bool, resolvedURL: String, surfaced: Bool = false) {
        self.urlID = urlID
        self.opened = opened
        self.resolvedURL = resolvedURL
        self.surfaced = surfaced
    }
}

// MARK: - google.search

/// Opens a Google search for a query in the browser (NIC-134). Like ``ProjectCapability``'s
/// path constraint, the destination is not free-form: the adapter builds the Google search URL
/// host-side (the host is fixed to `google.com`) and only the query varies, so untrusted data
/// can never choose the target host. The adapter prefers a running Google Chrome instance,
/// falling back to the default browser. Reusable by any "search the web for X" affordance.
public protocol GoogleSearchCapability: Sendable {
    func search(query: String) async throws -> GoogleSearchResult
}

public struct GoogleSearchResult: Equatable, Sendable {
    public let query: String
    public let opened: Bool
    /// The Google search URL that was opened.
    public let resolvedURL: String

    public init(query: String, opened: Bool, resolvedURL: String) {
        self.query = query
        self.opened = opened
        self.resolvedURL = resolvedURL
    }
}

// MARK: - messages.send

/// Sends one iMessage (quick-actions phase 4) — the only tool in the MVP that speaks to another
/// person.
///
/// **This is the one external write that never takes the user-authored exemption.** A calendar
/// event can be edited, a Linear ticket closed, a playlist deleted; a message lands on someone
/// else's device and cannot be unsent. So `messages.send` is `confirm_external_write` outright:
/// every send confirms, with the recipient named and the **body shown in full** — the disclosure
/// is the user re-reading their own message before it leaves, which is exactly the moment a typo
/// or a wrong recipient is catchable.
///
/// The body is passed to the adapter as an argument and never interpolated into a script, so
/// quotes and AppleScript keywords inside it are data rather than syntax.
public protocol MessagingCapability: Sendable {
    /// `targetKind` is `participant` (one person, by handle) or `chat` (an existing thread).
    func send(body: String, target: String, targetKind: String) async throws -> Bool
}

/// Someone (or some thread) a message can be sent to.
public struct MessageRecipient: Equatable, Sendable {
    /// The handle for a person, or the chat identifier for a thread.
    public let id: String
    public let name: String
    /// `participant` or `chat`.
    public let kind: String
    /// How many people are in the thread, for a group. Nil for one person.
    public let groupSize: Int?
    /// The phone number or Apple ID behind a person, shown so two "John Smith"s are separable.
    public let handle: String?

    public init(id: String, name: String, kind: String, groupSize: Int?, handle: String?) {
        self.id = id
        self.name = name
        self.kind = kind
        self.groupSize = groupSize
        self.handle = handle
    }
}

/// Reading who can be messaged is a **separate port** from sending — the fourth instance of that
/// split, and the one where it matters most: a surface that lists contacts must not be able to
/// reach the path that sends to them.
public protocol MessageRecipientsProviding: Sendable {
    func recipients() async throws -> [MessageRecipient]
}

// MARK: - spotify.createplaylist

/// Creates an empty playlist in the user's connected Spotify account (quick-actions phase 4).
///
/// Separate from ``SpotifyControlCapability`` even though both speak to the same account and share
/// one OAuth session: control is transport (play/pause/skip), this is a **write to the user's
/// library**, and it needs scopes control does not. Keeping them apart means a playback surface can
/// never reach the path that creates something.
public protocol SpotifyPlaylistCapability: Sendable {
    func createPlaylist(name: String, description: String?, isPublic: Bool) async throws -> SpotifyPlaylistResult
}

public struct SpotifyPlaylistResult: Equatable, Sendable {
    public let id: String
    public let name: String
    /// The playlist's Spotify URL **as returned by the API** — never constructed here. Nil when
    /// Spotify omitted it.
    public let url: String?

    public init(id: String, name: String, url: String?) {
        self.id = id
        self.name = name
        self.url = url
    }
}

// MARK: - linear.createissue

/// Creates one issue in the user's Linear workspace (quick-actions phase 4).
///
/// **Write only.** Reading the workspace (teams, projects, labels — what the form's dropdowns need)
/// is a separate concern that never crosses this port, the same split as
/// ``CalendarWritingCapability`` versus ``CalendarProvider``: a surface that only lists options can
/// never reach the path that files a ticket.
///
/// The API key is resolved by the adapter from the Keychain, never passed in — a token travelling
/// through the tool boundary would end up in a disclosure or a log.
public protocol LinearIssueCapability: Sendable {
    func createIssue(
        title: String,
        description: String?,
        teamID: String,
        projectID: String?,
        labelIDs: [String],
        priority: Int?
    ) async throws -> LinearIssueResult
}

public struct LinearIssueResult: Equatable, Sendable {
    /// The identifier Linear assigned, e.g. `NIC-176`.
    public let identifier: String
    /// The issue's web URL **as returned by Linear** — never constructed here, so a workspace
    /// slug we do not know can never be guessed wrong.
    public let url: String

    public init(identifier: String, url: String) {
        self.identifier = identifier
        self.url = url
    }
}

// MARK: - project.scaffold

/// Creates a new project folder under the projects root, with a `PROJECT.md` descriptor
/// (quick-actions phase 4).
///
/// A **project folder is a container, not a repository** (``ActiveProjectsProvider``): the repos
/// live one level inside it. So this deliberately does not `git init` anything — a project folder
/// that was itself a repo would be a different shape from every project the widget already reads.
///
/// Same containment invariant as ``GitCloneCapability``: the destination is resolved inside the
/// projects root and re-checked after standardizing, and an existing path is a refusal rather than
/// an overwrite. Nothing here runs a process.
public protocol ProjectScaffoldCapability: Sendable {
    func scaffold(
        name: String,
        location: String?,
        summary: String?,
        importance: Int?
    ) async throws -> ProjectScaffoldResult
}

public struct ProjectScaffoldResult: Equatable, Sendable {
    public let projectPath: String
    public let descriptorPath: String

    public init(projectPath: String, descriptorPath: String) {
        self.projectPath = projectPath
        self.descriptorPath = descriptorPath
    }
}

// MARK: - git.clone

/// Clones a git repository into a folder under the projects root (quick-actions phase 4).
///
/// Deliberately **not** a wrapper over ``ProcessCapability``'s hook path: a hook is free-form
/// configured shell, which is why `hook.run` is `shell`-class and confirms every run. This is one
/// fixed executable with a typed argument list — no shell, no caller-chosen program — so it is
/// honestly `local_write` and runs one-click, exactly like `project.open`.
///
/// Two invariants belong to the adapter, not the caller: the destination is resolved *inside* the
/// projects root and re-checked after standardizing (so `..` cannot escape), and a URL carrying
/// embedded credentials is refused outright rather than redacted, so a token can never reach the
/// command log in the first place.
public protocol GitCloneCapability: Sendable {
    func clone(repositoryURL: String, directory: String?) async throws -> GitCloneResult
}

public struct GitCloneResult: Equatable, Sendable {
    /// The absolute path the repository was cloned to, always inside the projects root.
    public let clonedPath: String
    /// The folder name the clone landed in.
    public let repositoryName: String

    public init(clonedPath: String, repositoryName: String) {
        self.clonedPath = clonedPath
        self.repositoryName = repositoryName
    }
}

// MARK: - youtube.search

/// Opens a YouTube search for a query in the browser (quick-actions phase 4). Deliberately a
/// **separate port** from ``GoogleSearchCapability`` rather than a `site:` parameter on it: the
/// whole safety property of both is that the destination host is a literal constant in the adapter,
/// and a host chosen by the caller — even from a closed set — would give that up for nothing. Two
/// small adapters keep "the query is only ever data" true by construction.
public protocol YouTubeSearchCapability: Sendable {
    func search(query: String) async throws -> YouTubeSearchResult
}

public struct YouTubeSearchResult: Equatable, Sendable {
    public let query: String
    public let opened: Bool
    /// The YouTube results URL that was opened.
    public let resolvedURL: String

    public init(query: String, opened: Bool, resolvedURL: String) {
        self.query = query
        self.opened = opened
        self.resolvedURL = resolvedURL
    }
}

// MARK: - spotify.control

/// Controls the user's Spotify playback (NIC-133): play/pause/next/previous, sent to the active
/// device via the Spotify Web API. Requires a connected account (a valid OAuth token) — the adapter
/// resolves it; a missing/dead authorization surfaces as ``NativeCapabilityError``. When there is no
/// active device to act on, the result reports `activeDevice: false` rather than erroring, so the
/// widget can guide the user honestly instead of appearing broken.
public protocol SpotifyControlCapability: Sendable {
    func control(action: String) async throws -> SpotifyControlResult
}

public struct SpotifyControlResult: Equatable, Sendable {
    public let action: String
    /// True when Spotify accepted the command; false when there was no active device.
    public let applied: Bool
    /// Whether there was an active Spotify device to control.
    public let activeDevice: Bool

    public init(action: String, applied: Bool, activeDevice: Bool) {
        self.action = action
        self.applied = applied
        self.activeDevice = activeDevice
    }
}

// MARK: - web.open

/// Opens an arbitrary https web address in the browser (NIC-127). Where ``URLCapability`` resolves
/// a *configured* reference id and ``GoogleSearchCapability`` builds a host-fixed search URL, this
/// opens a caller-supplied destination — a news article link. The destination is still constrained
/// (not allow-listed): the adapter validates the scheme (https only) and a present host host-side,
/// refusing anything else, so a malformed or non-https link from feed data is never opened. Prefers
/// a running Google Chrome instance, falling back to the default browser.
public protocol WebOpenCapability: Sendable {
    func open(url: String) async throws -> WebOpenResult
}

public struct WebOpenResult: Equatable, Sendable {
    /// The https URL that was opened.
    public let url: String
    public let opened: Bool

    public init(url: String, opened: Bool) {
        self.url = url
        self.opened = opened
    }
}

// MARK: - hook.run (process)

public protocol ProcessCapability: Sendable {
    func run(_ invocation: HookInvocation) async throws -> ProcessRunResult
}

public struct ProcessRunResult: Equatable, Sendable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
    public let environment: [String: String]
    public let timedOut: Bool
    public let durationMs: Int

    public init(exitCode: Int, stdout: String, stderr: String, environment: [String: String], timedOut: Bool, durationMs: Int) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.environment = environment
        self.timedOut = timedOut
        self.durationMs = durationMs
    }
}

// MARK: - system.status.read

public enum SystemMetricID: String, Sendable, CaseIterable {
    case cpu, memory, network, battery, display
}

/// Per-metric availability, mirroring the canonical system-metric fixtures
/// (PRD §13.2): a metric can be present, missing, stale, still loading, or
/// disconnected independently of the others (FR-MOD-04).
public enum MetricAvailability: String, Sendable, Equatable {
    case available, unavailable, stale, loading, disconnected
}

public struct SystemMetricReading: Equatable, Sendable {
    public let id: SystemMetricID
    public let availability: MetricAvailability
    public let value: Double?
    public let unit: String?

    public init(id: SystemMetricID, availability: MetricAvailability, value: Double?, unit: String?) {
        self.id = id
        self.availability = availability
        self.value = value
        self.unit = unit
    }
}

public protocol SystemStatusCapability: Sendable {
    func readMetrics(_ ids: [SystemMetricID]) async throws -> [SystemMetricReading]
}

// MARK: - network.speed.test

/// The outcome of an on-demand internet capacity measurement (NIC-135). The
/// figures are a point-in-time measurement in Mbps; a direction is `nil` when the
/// test could not measure it. This is a read — it measures and mutates nothing.
public struct NetworkSpeedTestReading: Equatable, Sendable {
    public enum Status: String, Sendable, Equatable {
        /// Both directions measured.
        case ok
        /// Exactly one direction measured (the other is `nil`).
        case partial
        /// The test could not run (no route, tool missing, timed out).
        case unavailable
    }

    public let status: Status
    public let downloadMbps: Double?
    public let uploadMbps: Double?

    public init(status: Status, downloadMbps: Double?, uploadMbps: Double?) {
        self.status = status
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
    }
}

/// Runs a bounded, on-demand internet capacity measurement (NIC-135). macOS-native
/// (Apple's `networkQuality`); the pre-Mac mock reports unavailable. Read-only:
/// unlike `hook.run`, it is a specific, non-mutating diagnostic, not arbitrary
/// shell — so it is classified and confirmed as a read (descriptor risk
/// `read_only`).
public protocol NetworkSpeedTestCapability: Sendable {
    func measure() async throws -> NetworkSpeedTestReading
}

// MARK: - apps.list

/// One installed application, discovered read-only (NIC-119). `iconPNGBase64`
/// is a size-capped PNG rendered by the platform adapter; nil when no icon
/// could be produced — the UI falls back honestly, this layer never invents one.
public struct InstalledApplication: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let iconPNGBase64: String?

    public init(bundleID: String, name: String, iconPNGBase64: String?) {
        self.bundleID = bundleID
        self.name = name
        self.iconPNGBase64 = iconPNGBase64
    }
}

/// The complete discovery result; `truncated` is honest about any cap applied.
public struct AppDiscoveryResult: Equatable, Sendable {
    public let apps: [InstalledApplication]
    public let truncated: Bool

    public init(apps: [InstalledApplication], truncated: Bool) {
        self.apps = apps
        self.truncated = truncated
    }
}

/// Read-only enumeration of installed applications (NIC-119): feeds the More
/// Apps picker and pinning. Never launches, moves, or modifies anything.
public protocol AppDiscoveryCapability: Sendable {
    func listApplications(includeIcons: Bool) async throws -> AppDiscoveryResult
}

// MARK: - secret

public protocol SecretCapability: Sendable {
    func resolve(reference: String) async throws -> SecretResolution
}

/// The result of resolving a *logical* secret reference. It never exposes the
/// secret value — only whether the reference is bound — so secrets stay logical
/// names end to end (FR-CFG-03, NIC-34).
public struct SecretResolution: Equatable, Sendable {
    public let reference: String
    public let isResolved: Bool

    public init(reference: String, isResolved: Bool) {
        self.reference = reference
        self.isResolved = isResolved
    }
}

// MARK: - workspace windows

/// Hide-and-return of whole applications for "Windows Stored by Mode" (NIC-85).
///
/// Permission-free by design: implemented with application-level hide/unhide
/// (`NSRunningApplication`), never Accessibility window manipulation — geometry
/// restore is a separate, gated capability. All operations are best-effort and
/// report the bundle ids actually affected; an id that is not running is simply
/// not in the result, never an error.
///
/// DECISION (NIC-85, 2026-07-06): storage is app-level, so an application used
/// in two modes shares all of its windows between them — opening a
/// hidden-by-mode app surfaces every window (macOS activation un-hides the whole
/// app; there is no universal new-window API). Accepted MVP behavior; per-mode
/// window sets belong to the post-MVP deeper-window-management pool (PRD §5.3),
/// where an opt-in `createsNewApplicationInstance` reference flag is the known
/// 80% approach for single-instance-forwarding apps like Chrome.
public protocol WorkspaceWindowsCapability: Sendable {
    /// Bundle ids of regular, currently visible (un-hidden) applications,
    /// excluding the host app itself.
    func visibleApplicationBundleIDs() async throws -> [String]

    /// Hides the given applications; returns the ids actually hidden.
    func hideApplications(bundleIDs: [String]) async throws -> [String]

    /// Un-hides the given applications where still running; returns the ids
    /// actually returned. Never launches anything.
    func unhideApplications(bundleIDs: [String]) async throws -> [String]
}

// MARK: - application lifecycle

/// Enumerate and quit running applications — the "close all windows" capability
/// (NIC-143). Distinct from ``WorkspaceWindowsCapability`` (which only hides): this
/// terminates apps, so its one tool is destructive and confirmation-gated.
///
/// The quit is a *graceful* request (owner decision, 2026-07-15): the app receives a
/// normal terminate and may run its own save/quit path — never a forced kill that
/// discards unsaved work. Best-effort throughout: a not-running id is simply absent
/// from a result, never an error, and the host application is never a target.
public protocol ApplicationLifecycleCapability: Sendable {
    /// Bundle ids of regular running applications — including hidden ones (unlike
    /// ``WorkspaceWindowsCapability/visibleApplicationBundleIDs()``) — excluding the
    /// host app. This is the quit-all target set: everything the user could quit,
    /// across every mode.
    func regularRunningApplicationBundleIDs() async throws -> [String]

    /// Requests a graceful quit of each application; returns the ids actually asked
    /// to terminate (an id no longer running is simply absent).
    func quitApplications(bundleIDs: [String]) async throws -> [String]

    /// Requests a graceful quit of **the host application itself** — the complement of
    /// ``quitApplications(bundleIDs:)``, which always excludes the host.
    ///
    /// It takes no target by design: quitting CerebralHelm and quitting someone else's app
    /// are different capabilities, and keeping them apart means no caller can reach one
    /// through the other. Returns once termination has been *requested*; the process is on
    /// its way out, so there is no later status to observe.
    func quitHostApplication() async throws
}

/// Writes an event into the user's calendar (`calendar.createevent`).
///
/// Deliberately a SEPARATE port from `CalendarProvider`, which reads. A reader should not have to
/// implement writing to satisfy a protocol, and keeping the two apart means the widgets/publishers
/// that only read the calendar cannot reach the write path at all.
///
/// `startsAt`/`endsAt` are local wall-clock ISO strings, matching the read side's convention
/// (NIC-126): a time a user typed into a form means the time they meant, in their own zone.
public protocol CalendarWritingCapability: Sendable {
    /// Creates the event and returns its store identifier plus the calendar it landed in, so the
    /// result can say WHERE it went rather than only that it worked. A `nil` `calendarID` writes
    /// to the host's default calendar rather than guessing which one was meant.
    func createEvent(
        title: String,
        startsAt: String,
        endsAt: String,
        calendarID: String?,
        location: String?,
        notes: String?
    ) async throws -> (eventID: String, calendarTitle: String?)
}

// MARK: - application windows (window navigator)

/// One open window in the window-navigator inventory (NIC-143).
public struct AppWindowInfo: Equatable, Sendable {
    /// Opaque, stable window identifier — the stringified `CGWindowID` on macOS
    /// (owner decision). Callers pass it back to minimize/surface/close a window;
    /// it is never parsed by the UI.
    public let id: String
    /// The window's title (from Accessibility, so it needs no Screen Recording
    /// permission). May be empty when a window exposes none.
    public let title: String
    /// Whether the window is currently minimized (in the Dock).
    public let minimized: Bool

    public init(id: String, title: String, minimized: Bool) {
        self.id = id
        self.title = title
        self.minimized = minimized
    }
}

/// One application's open windows, grouped for the navigator's app-stacked cards
/// (NIC-143). `windows` preserves front-to-back order.
public struct AppWindowGroup: Equatable, Sendable {
    public let bundleID: String
    public let appName: String
    /// The application's icon as a base64 PNG, for the card mark; `nil` when it cannot
    /// be rendered (the UI falls back to a category glyph).
    public let appIconPNGBase64: String?
    public let windows: [AppWindowInfo]

    public init(bundleID: String, appName: String, appIconPNGBase64: String? = nil, windows: [AppWindowInfo]) {
        self.bundleID = bundleID
        self.appName = appName
        self.appIconPNGBase64 = appIconPNGBase64
        self.windows = windows
    }
}

/// Enumerate and act on individual open windows — the window-navigator capability
/// (NIC-143). Distinct from ``WorkspaceWindowsCapability`` (whole-app hide) and
/// ``WindowCapability`` (main-window arrange): this addresses *each* window by a stable
/// id, so the navigator can surface, minimize, or close one window of a multi-window
/// app. Enumeration and minimize/surface use Accessibility (already granted for
/// arrangement); closing a single window is a `local_write`-equivalent — the same
/// as pressing the window's own close button — so navigator actions run without a
/// per-press confirmation, like the layout ops. Best-effort: an unknown id is simply
/// a `false` result, never an error.
public protocol AppWindowsCapability: Sendable {
    /// Every open window on screen, grouped by application (NIC-143).
    func listWindows() async throws -> [AppWindowGroup]
    /// Minimize the window to the Dock; returns whether it was found and minimized.
    func minimize(windowID: String) async throws -> Bool
    /// Bring the window to the front (un-minimizing/activating as needed); returns
    /// whether it was found and surfaced.
    func surface(windowID: String) async throws -> Bool
    /// Close the window (its own close button); returns whether it was found and closed.
    func close(windowID: String) async throws -> Bool
}

// MARK: - window

/// The named-frame vocabulary for window arrangement (NIC-88). Raw values match
/// the `window-arrange-input` contract enum; frames are resolved against the
/// target ``WindowDisplay``'s visible area by the platform adapter — callers never
/// supply coordinates.
public enum WindowFrame: String, Sendable, CaseIterable {
    case full
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case leftTwoThirds = "left-two-thirds"
    case rightThird = "right-third"
    case leftThird = "left-third"
    case rightTwoThirds = "right-two-thirds"
    case centered
}

/// One application's arrangement outcome — honest partials, never a silent skip.
public enum WindowArrangeOutcome: Equatable, Sendable {
    case arranged
    /// The application is not running; windows are only arranged, never launched.
    case notRunning
    /// The application exposes no controllable window (reliability gate, NIC-88).
    case unsupported(String)
}

/// Which display an arrangement targets (NIC-142 layout mode). Mirrors the
/// `window-arrange-input` contract's `display` enum; the platform adapter resolves
/// each named frame against the chosen display's visible area, degrading
/// `secondary` to the primary display when no second display is attached.
public enum WindowDisplay: String, Sendable, CaseIterable {
    case primary
    case secondary
}

public protocol WindowCapability: Sendable {
    func inspect() async throws -> [WindowInfo]

    /// Move/resize the application's main window into a named frame on the chosen
    /// display. Throws `NativeCapabilityError.permissionDenied` when the
    /// Accessibility permission is not granted (FR-SAF-07 — a capability error,
    /// never a prompt loop).
    func arrange(bundleID: String, frame: WindowFrame, display: WindowDisplay) async throws -> WindowArrangeOutcome

    /// Read the application's main window frame for a workspace snapshot
    /// ("Windows Stored by Mode" geometry, NIC-85). `nil` when the application
    /// is not running or exposes no readable window; throws `permissionDenied`
    /// when Accessibility is not granted.
    func captureFrame(bundleID: String) async throws -> WindowRect?

    /// Reapply a stored main-window frame. Same outcome vocabulary as `arrange`;
    /// throws `permissionDenied` when Accessibility is not granted.
    func restoreFrame(bundleID: String, rect: WindowRect) async throws -> WindowArrangeOutcome

    /// The primary display's visible area (NIC-142 live capture), in the same
    /// coordinate space `captureFrame` reports, so a captured window rect can be
    /// snapped to a named frame. `nil` when no display is attached; throws
    /// `permissionDenied` when Accessibility is not granted.
    func visibleFrame() async throws -> WindowRect?
}

public extension WindowCapability {
    /// Arrange on the primary display — the default target when a caller does not
    /// specify a display (preserves the pre-NIC-142 single-display signature).
    func arrange(bundleID: String, frame: WindowFrame) async throws -> WindowArrangeOutcome {
        try await arrange(bundleID: bundleID, frame: frame, display: .primary)
    }
}

public struct WindowInfo: Equatable, Sendable {
    public let id: String
    public let title: String
    public let isFocused: Bool

    public init(id: String, title: String, isFocused: Bool) {
        self.id = id
        self.title = title
        self.isFocused = isFocused
    }
}
