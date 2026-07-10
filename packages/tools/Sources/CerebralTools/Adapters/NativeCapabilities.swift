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

// MARK: - url.open

public protocol URLCapability: Sendable {
    func open(urlID: String) async throws -> URLOpenResult
}

public struct URLOpenResult: Equatable, Sendable {
    public let urlID: String
    public let opened: Bool
    public let resolvedURL: String

    public init(urlID: String, opened: Bool, resolvedURL: String) {
        self.urlID = urlID
        self.opened = opened
        self.resolvedURL = resolvedURL
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

// MARK: - window

/// The named-frame vocabulary for window arrangement (NIC-88). Raw values match
/// the `window-arrange-input` contract enum; frames are resolved against the
/// primary display's visible area by the platform adapter — callers never supply
/// coordinates.
public enum WindowFrame: String, Sendable, CaseIterable {
    case full
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case leftTwoThirds = "left-two-thirds"
    case rightThird = "right-third"
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

public protocol WindowCapability: Sendable {
    func inspect() async throws -> [WindowInfo]

    /// Move/resize the application's main window into a named frame. Throws
    /// `NativeCapabilityError.permissionDenied` when the Accessibility permission
    /// is not granted (FR-SAF-07 — a capability error, never a prompt loop).
    func arrange(bundleID: String, frame: WindowFrame) async throws -> WindowArrangeOutcome

    /// Read the application's main window frame for a workspace snapshot
    /// ("Windows Stored by Mode" geometry, NIC-85). `nil` when the application
    /// is not running or exposes no readable window; throws `permissionDenied`
    /// when Accessibility is not granted.
    func captureFrame(bundleID: String) async throws -> WindowRect?

    /// Reapply a stored main-window frame. Same outcome vocabulary as `arrange`;
    /// throws `permissionDenied` when Accessibility is not granted.
    func restoreFrame(bundleID: String, rect: WindowRect) async throws -> WindowArrangeOutcome
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
