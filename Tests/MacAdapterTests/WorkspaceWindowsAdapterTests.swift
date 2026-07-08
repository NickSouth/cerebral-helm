#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

/// "Windows Stored by Mode" (NIC-85): the native adapter selects only regular,
/// visible, non-self applications, and hide/return are best-effort — ids report
/// only when the platform accepted the request.

private struct FakeRunningApplications: RunningApplicationSource {
    var apps: [RunningApplicationInfo]
    var accepting: Set<String>
    var ownBundleID: String? = "local.cerebralhelm.CerebralHelm"

    func runningApplications() -> [RunningApplicationInfo] { apps }
    func hide(bundleID: String) -> Bool { accepting.contains(bundleID) }
    func unhide(bundleID: String) -> Bool { accepting.contains(bundleID) }
}

@Test("visible applications exclude background apps, hidden apps, and the host itself")
func visibleSelectionIsHonest() async throws {
    let capability = MacWorkspaceWindowsCapability(source: FakeRunningApplications(
        apps: [
            RunningApplicationInfo(bundleID: "com.microsoft.VSCode", isRegular: true, isHidden: false),
            RunningApplicationInfo(bundleID: "com.apple.Terminal", isRegular: true, isHidden: true),
            RunningApplicationInfo(bundleID: "com.apple.dock.helper", isRegular: false, isHidden: false),
            RunningApplicationInfo(bundleID: "local.cerebralhelm.CerebralHelm", isRegular: true, isHidden: false),
        ],
        accepting: []
    ))

    #expect(try await capability.visibleApplicationBundleIDs() == ["com.microsoft.VSCode"])
}

@Test("hide and return report only the applications the platform accepted, never the host")
func hideAndReturnAreBestEffort() async throws {
    let capability = MacWorkspaceWindowsCapability(source: FakeRunningApplications(
        apps: [],
        accepting: ["com.microsoft.VSCode"]
    ))

    let hidden = try await capability.hideApplications(
        bundleIDs: ["com.microsoft.VSCode", "com.quit.App", "local.cerebralhelm.CerebralHelm"]
    )
    #expect(hidden == ["com.microsoft.VSCode"])

    let returned = try await capability.unhideApplications(
        bundleIDs: ["com.quit.App", "com.microsoft.VSCode"]
    )
    #expect(returned == ["com.microsoft.VSCode"])
}
#endif
