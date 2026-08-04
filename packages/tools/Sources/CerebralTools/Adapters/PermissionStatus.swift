/// Platform permission status for one logical permission id (NIC-83,
/// FR-SAF-07, FR-SHL-06). Logical ids are declared by tool descriptors
/// (`requiredPermissions`); the platform adapter maps each to a real check.
public enum PermissionStatus: String, Sendable, Equatable {
    /// The platform granted the permission.
    case granted
    /// The platform denied the permission. The owning capability degrades with
    /// guidance — never a repeated prompt or a bypass attempt (FR-SAF-07).
    case denied
    /// The user has not been asked yet. Treated as unavailable-with-guidance:
    /// prompting happens only at point of use by the adapter that needs it,
    /// never proactively ("only required permissions are requested").
    case notDetermined
    /// No platform gate exists for this permission on this platform — the
    /// deterministic policy layer alone governs it.
    case notRequired

    /// Whether a capability requiring this permission may report available.
    public var satisfiesRequirement: Bool {
        switch self {
        case .granted, .notRequired: return true
        case .denied, .notDetermined: return false
        }
    }
}

/// Read-only permission lookup the composition layer consults when deriving
/// capability flags. Implementations must never trigger a system prompt.
public protocol PermissionChecking: Sendable {
    func status(of permissionID: String) -> PermissionStatus
}

/// User-facing guidance for a permission: why it is needed and, where macOS
/// supports it, the System Settings deep link that grants it.
public struct PermissionGuidance: Sendable, Equatable {
    public let explanation: String
    public let settingsDeepLink: String?

    public init(explanation: String, settingsDeepLink: String? = nil) {
        self.explanation = explanation
        self.settingsDeepLink = settingsDeepLink
    }
}

/// Guidance for every logical permission the MVP descriptors declare, plus the
/// known upcoming TCC permission (accessibility, NIC-88). Unknown ids get an
/// honest generic message rather than silence.
public enum PermissionCatalog {
    public static func guidance(for permissionID: String) -> PermissionGuidance {
        switch permissionID {
        case "accessibility":
            return PermissionGuidance(
                explanation: "CerebralHelm needs the Accessibility permission to arrange application windows.",
                settingsDeepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        case "location":
            return PermissionGuidance(
                explanation: "CerebralHelm needs Location access to show the weather for where you are.",
                settingsDeepLink: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            )
        case "application_launch":
            return PermissionGuidance(explanation: "Opening configured applications requires no additional macOS permission.")
        case "url_open":
            return PermissionGuidance(explanation: "Opening configured URLs requires no additional macOS permission.")
        case "allowlisted_process_execution":
            return PermissionGuidance(explanation: "Running configured hooks requires no additional macOS permission; every run is confirmation-gated.")
        case "knowledge_root_read", "knowledge_root_write":
            return PermissionGuidance(explanation: "Reading and writing your knowledge notes uses your own files; no additional macOS permission is required.")
        case "system_metrics_read":
            return PermissionGuidance(explanation: "Reading CPU, memory, network, and battery metrics requires no additional macOS permission.")
        case "projects_root_write":
            return PermissionGuidance(explanation: "Cloning into your projects folder uses your own files; no additional macOS permission is required.")
        case "mode_plan_execute":
            return PermissionGuidance(explanation: "Applying a mode executes only its planned, policy-gated actions; no additional macOS permission is required.")
        default:
            return PermissionGuidance(
                explanation: "The permission '\(permissionID)' is not recognized by this build; the capability that requires it stays unavailable."
            )
        }
    }
}
