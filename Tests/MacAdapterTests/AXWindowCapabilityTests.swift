#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

/// `window.arrange` native adapter (NIC-88): trust-gated, best-effort, honest
/// outcomes, deterministic named-frame geometry.

private struct FakeAXWindows: AXWindowSurface {
    var isProcessTrusted: Bool = true
    var primaryVisibleFrame: CGRect? = CGRect(x: 0, y: 25, width: 1200, height: 775)
    var pidsByBundleID: [String: [pid_t]] = [:]
    var settablePIDs: Set<pid_t> = []

    func runningProcessIDs(bundleID: String) -> [pid_t] { pidsByBundleID[bundleID] ?? [] }
    func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool { settablePIDs.contains(pid) }
}

@Test("an untrusted process is a permission-denied capability error, never a prompt")
func untrustedProcessIsDenied() async throws {
    let capability = AXWindowCapability(surface: FakeAXWindows(isProcessTrusted: false))
    await #expect(throws: NativeCapabilityError.permissionDenied) {
        _ = try await capability.arrange(bundleID: "com.microsoft.VSCode", frame: .full)
    }
}

@Test("not-running and no-controllable-window are honest outcomes")
func outcomesAreHonest() async throws {
    let capability = AXWindowCapability(surface: FakeAXWindows(
        pidsByBundleID: ["com.apple.Terminal": [42]],
        settablePIDs: []
    ))
    #expect(try await capability.arrange(bundleID: "com.quit.App", frame: .full) == .notRunning)
    guard case .unsupported = try await capability.arrange(bundleID: "com.apple.Terminal", frame: .full) else {
        Issue.record("Expected unsupported for an app with no settable main window.")
        return
    }
}

@Test("a settable main window arranges")
func settableWindowArranges() async throws {
    let capability = AXWindowCapability(surface: FakeAXWindows(
        pidsByBundleID: ["com.microsoft.VSCode": [7]],
        settablePIDs: [7]
    ))
    #expect(try await capability.arrange(bundleID: "com.microsoft.VSCode", frame: .leftHalf) == .arranged)
}

@Test("named frames resolve to deterministic geometry within the visible area")
func frameGeometryIsDeterministic() {
    let visible = CGRect(x: 0, y: 25, width: 1200, height: 775)

    #expect(AXWindowCapability.resolve(.full, in: visible) == visible)
    #expect(AXWindowCapability.resolve(.leftHalf, in: visible) == CGRect(x: 0, y: 25, width: 600, height: 775))
    #expect(AXWindowCapability.resolve(.rightHalf, in: visible) == CGRect(x: 600, y: 25, width: 600, height: 775))
    #expect(AXWindowCapability.resolve(.leftTwoThirds, in: visible) == CGRect(x: 0, y: 25, width: 800, height: 775))
    #expect(AXWindowCapability.resolve(.rightThird, in: visible) == CGRect(x: 800, y: 25, width: 400, height: 775))
    #expect(AXWindowCapability.resolve(.bottomHalf, in: visible) == CGRect(x: 0, y: 412.5, width: 1200, height: 387.5))
}
#endif
