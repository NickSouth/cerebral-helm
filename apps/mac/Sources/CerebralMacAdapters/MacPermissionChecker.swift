// Platform permission status (NIC-83, MAC-ADAPTER-5).
#if canImport(AppKit)
import ApplicationServices
import CoreLocation
import Foundation
import CerebralTools

/// Maps the logical permission ids declared by tool descriptors onto real macOS
/// checks (FR-SAF-07, FR-SHL-06).
///
/// The MVP tool set needs no TCC permission on an unsandboxed app (ADR-008):
/// launching apps, opening URLs, running allowlisted hooks, reading the
/// knowledge root, and sampling system metrics are all governed by the
/// deterministic policy layer alone, so those report `.notRequired` — honestly
/// "no platform gate exists", not "granted by the user".
///
/// `accessibility` is the one real TCC permission on the roadmap (window
/// arrangement, MAC-WORKSPACE-3): its status is *read* via
/// `AXIsProcessTrusted()`, which never prompts — prompting stays at point of
/// use, by the adapter that genuinely needs it ("only required permissions are
/// requested"). Unknown ids report `.notDetermined`, degrading their capability
/// with guidance rather than silently passing.
public struct MacPermissionChecker: PermissionChecking {
    public init() {}

    public func status(of permissionID: String) -> PermissionStatus {
        switch permissionID {
        case "application_launch",
             "url_open",
             "allowlisted_process_execution",
             "knowledge_root_read",
             "knowledge_root_write",
             "system_metrics_read",
             "mode_plan_execute",
             "projects_root_write":
            return .notRequired
        case "accessibility":
            return AXIsProcessTrusted() ? .granted : .denied
        case "location":
            // The weather widget's location fix (NIC-169). Read the live CoreLocation
            // authorization without prompting — the prompt stays at point of use in
            // `CoreLocationProvider`. Reading the status is a plain property access.
            return CoreLocationProvider.permissionStatus(from: CLLocationManager().authorizationStatus)
        default:
            return .notDetermined
        }
    }
}
#endif
