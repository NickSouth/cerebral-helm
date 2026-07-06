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

public protocol WindowCapability: Sendable {
    func inspect() async throws -> [WindowInfo]
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
