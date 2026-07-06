// NIC-83 (MAC-ADAPTER-5): platform permission status.
#if canImport(AppKit)
import Testing

import CerebralMacAdapters
import CerebralTools

@Test("every MVP logical permission is honestly notRequired on an unsandboxed app")
func mvpPermissionsAreNotRequired() {
    let checker = MacPermissionChecker()
    let mvpPermissions = [
        "application_launch", "url_open", "allowlisted_process_execution",
        "knowledge_root_read", "knowledge_root_write", "system_metrics_read",
        "mode_plan_execute",
    ]
    for permission in mvpPermissions {
        #expect(checker.status(of: permission) == .notRequired, Comment(rawValue: permission))
        #expect(checker.status(of: permission).satisfiesRequirement)
    }
}

@Test("accessibility reads the real TCC state without prompting; unknown ids are conservative")
func accessibilityAndUnknownPermissions() {
    let checker = MacPermissionChecker()
    // The test process's actual Accessibility grant is environment-dependent;
    // the contract is that the check answers granted-or-denied (a read, never a
    // prompt) rather than notRequired.
    let accessibility = checker.status(of: "accessibility")
    #expect(accessibility == .granted || accessibility == .denied)

    // A permission this build does not recognize must not silently pass.
    #expect(checker.status(of: "future_unknown_permission") == .notDetermined)
    #expect(!checker.status(of: "future_unknown_permission").satisfiesRequirement)
}
#endif
