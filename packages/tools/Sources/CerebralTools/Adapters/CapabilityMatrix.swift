/// The set of native capabilities present in the current runtime.
///
/// Capability flags drive availability: a tool whose required capability is
/// absent renders an unavailable state rather than failing or blocking portable
/// workflows (FR-SHL-06, AC-32.2).
public struct CapabilityMatrix: Sendable {
    private let available: Set<String>

    public init(available: Set<String>) {
        self.available = available
    }

    public func isAvailable(_ capability: String) -> Bool {
        available.contains(capability)
    }

    /// Stable capability identifiers, matching tool descriptors'
    /// `adapterRequirements.capabilities`.
    public enum Capability {
        public static let appOpen = "app.open"
        public static let projectOpen = "project.open"
        public static let urlOpen = "url.open"
        public static let hookRun = "hook.run"
        public static let systemStatusRead = "system.status.read"
        public static let networkSpeedTest = "network.speed.test"
        public static let secret = "secret"
        public static let window = "window"
        public static let workspaceWindows = "workspace.windows"
        public static let appsList = "apps.list"
        public static let applicationLifecycle = "application.lifecycle"
        public static let googleSearch = "google.search"
        public static let webOpen = "web.open"

        public static let all: Set<String> = [appOpen, projectOpen, urlOpen, hookRun, systemStatusRead, networkSpeedTest, secret, window, workspaceWindows, appsList, applicationLifecycle, googleSearch, webOpen]
    }

    /// Every mock capability available — the contract-suite default.
    public static let allAvailable = CapabilityMatrix(available: Capability.all)

    /// No native capability available — e.g. a degraded or unsupported runtime.
    public static let none = CapabilityMatrix(available: [])
}

/// A deterministic fault a mock can inject to reproduce a canonical failure
/// fixture (PRD §13.2, AC-32.3), independent of the capability matrix.
public enum MockFault: Equatable, Sendable {
    case none
    case unavailable
    case permissionDenied
    case notFound
    case timeout
    case cancelled
    case adapterFailure(String)
}

/// Shared gate every mock applies before producing a result: first the
/// capability matrix (AC-32.2), then any injected fault (AC-32.3).
enum CapabilityGate {
    static func check(_ capability: String, matrix: CapabilityMatrix, fault: MockFault, subject: String? = nil) throws {
        guard matrix.isAvailable(capability) else { throw NativeCapabilityError.unavailable }

        switch fault {
        case .none:
            return
        case .unavailable:
            throw NativeCapabilityError.unavailable
        case .permissionDenied:
            throw NativeCapabilityError.permissionDenied
        case .notFound:
            throw NativeCapabilityError.notFound(subject ?? capability)
        case .timeout:
            throw NativeCapabilityError.timedOut
        case .cancelled:
            throw NativeCapabilityError.cancelled
        case let .adapterFailure(message):
            throw NativeCapabilityError.adapterFailure(message)
        }
    }
}
