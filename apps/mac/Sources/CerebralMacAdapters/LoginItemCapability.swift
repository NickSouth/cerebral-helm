// Login item registration + single-instance guard (NIC-89, FR-SHL-01).
#if canImport(AppKit)
import AppKit
import Foundation
import ServiceManagement

/// The login item's OS-owned state. Raw values cross the private shellControl
/// channel to the settings "Startup" panel — the OS is the source of truth,
/// never the settings store (a stored flag could silently diverge from what
/// System Settings shows).
public enum LoginItemStatus: String, Sendable {
    case enabled
    /// Registered but the user must approve it in System Settings → General →
    /// Login Items before it takes effect.
    case requiresApproval = "requires-approval"
    case notRegistered = "not-registered"
    /// The service definition could not be found (unexpected for the main app).
    case notFound = "not-found"
}

/// Seam over `SMAppService.mainApp` so shell wiring is testable and the
/// ServiceManagement dependency stays in one place.
public protocol LoginItemManaging: Sendable {
    func status() -> LoginItemStatus
    /// Registers/unregisters the main app as a login item and returns the OS's
    /// resulting status. Reversible by design (NIC-89 AC); a thrown error means
    /// the OS refused — nothing to roll back, the status read stays honest.
    func setEnabled(_ enabled: Bool) throws -> LoginItemStatus
}

/// The live `SMAppService` binding (macOS 13+). Registration launches the same
/// binary through the same validated bootstrap pre-flight — a login launch has
/// no special path (NIC-89 AC).
public struct SMAppServiceLoginItem: LoginItemManaging {
    public init() {}

    public func status() -> LoginItemStatus {
        Self.map(SMAppService.mainApp.status)
    }

    public func setEnabled(_ enabled: Bool) throws -> LoginItemStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return status()
    }

    /// Public for the mapping test — every OS status maps to exactly one shell status.
    public static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
}

/// Duplicate-process guard (NIC-89 AC): a second launch focuses the existing
/// instance and exits before the startup pre-flight, so two processes can never
/// race the same operational database.
public enum SingleInstanceGuard {
    /// The already-running instance of this bundle id, if any (excluding this
    /// process). A nil bundle id (unbundled test runner) never matches.
    public static func existingInstance(
        bundleID: String?, currentPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> NSRunningApplication? {
        guard let bundleID else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID }
    }
}
#endif
