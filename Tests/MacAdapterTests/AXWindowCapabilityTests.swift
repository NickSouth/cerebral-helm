#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralMacAdapters
import CerebralTools

/// `window.arrange` native adapter (NIC-88): trust-gated, best-effort, honest
/// outcomes, deterministic named-frame geometry.

private struct FakeAXWindows: AXWindowSurface {
    var isProcessTrusted: Bool = true
    var visibleFrames: [WindowDisplay: CGRect] = [.primary: CGRect(x: 0, y: 25, width: 1200, height: 775)]
    var pidsByBundleID: [String: [pid_t]] = [:]
    var settablePIDs: Set<pid_t> = []
    var framesByPID: [pid_t: CGRect] = [:]

    func visibleFrame(for display: WindowDisplay) -> CGRect? { visibleFrames[display] }
    func runningProcessIDs(bundleID: String) -> [pid_t] { pidsByBundleID[bundleID] ?? [] }
    func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool { settablePIDs.contains(pid) }
    func mainWindowFrame(pid: pid_t) -> CGRect? { framesByPID[pid] }
}

/// Records the frames handed to `setMainWindowFrame` so tests can assert *which*
/// display's visible area an arrangement resolved against.
private final class RecordingAXWindows: AXWindowSurface, @unchecked Sendable {
    var isProcessTrusted = true
    var visibleFrames: [WindowDisplay: CGRect] = [:]
    var pidsByBundleID: [String: [pid_t]] = [:]
    var settablePIDs: Set<pid_t> = []
    private(set) var recordedFrames: [CGRect] = []

    func visibleFrame(for display: WindowDisplay) -> CGRect? { visibleFrames[display] }
    func runningProcessIDs(bundleID: String) -> [pid_t] { pidsByBundleID[bundleID] ?? [] }
    func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool {
        recordedFrames.append(frame)
        return settablePIDs.contains(pid)
    }
    func mainWindowFrame(pid: pid_t) -> CGRect? { nil }
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

@Test("frame capture reads the main window and reports nil for unreadable apps (NIC-85 geometry)")
func captureFrameIsHonest() async throws {
    let capability = AXWindowCapability(surface: FakeAXWindows(
        pidsByBundleID: [
            "com.microsoft.VSCode": [7],
            "com.apple.Terminal": [8],
        ],
        framesByPID: [7: CGRect(x: 10, y: 30, width: 640, height: 480)]
    ))

    #expect(try await capability.captureFrame(bundleID: "com.microsoft.VSCode")
        == WindowRect(x: 10, y: 30, width: 640, height: 480))
    // A running app with no readable window is nil, never a guess.
    #expect(try await capability.captureFrame(bundleID: "com.apple.Terminal") == nil)
    // Untrusted process: permission denied, not a silent nil.
    let untrusted = AXWindowCapability(surface: FakeAXWindows(isProcessTrusted: false))
    await #expect(throws: NativeCapabilityError.permissionDenied) {
        _ = try await untrusted.captureFrame(bundleID: "com.microsoft.VSCode")
    }
}

@Test("a stored frame restores through the same settable-window gate")
func restoreFrameAppliesStoredGeometry() async throws {
    let capability = AXWindowCapability(surface: FakeAXWindows(
        pidsByBundleID: ["com.microsoft.VSCode": [7]],
        settablePIDs: [7]
    ))
    let outcome = try await capability.restoreFrame(
        bundleID: "com.microsoft.VSCode",
        rect: WindowRect(x: 10, y: 30, width: 640, height: 480)
    )
    #expect(outcome == .arranged)
    #expect(try await capability.restoreFrame(
        bundleID: "com.quit.App", rect: WindowRect(x: 0, y: 0, width: 1, height: 1)
    ) == .notRunning)
}

@Test("an arrangement targets the requested display's visible area (NIC-142)")
func arrangeTargetsChosenDisplay() async throws {
    let primary = CGRect(x: 0, y: 25, width: 1200, height: 775)
    let secondary = CGRect(x: 1200, y: 0, width: 1000, height: 1000)
    let surface = RecordingAXWindows()
    surface.visibleFrames = [.primary: primary, .secondary: secondary]
    surface.pidsByBundleID = ["com.microsoft.VSCode": [7]]
    surface.settablePIDs = [7]
    let capability = AXWindowCapability(surface: surface)

    // A full frame on the secondary display resolves to the secondary's rect.
    #expect(try await capability.arrange(bundleID: "com.microsoft.VSCode", frame: .full, display: .secondary) == .arranged)
    #expect(surface.recordedFrames == [secondary])
}

@Test("a secondary target degrades to the primary display when only one is attached")
func secondaryDegradesToPrimary() async throws {
    let primary = CGRect(x: 0, y: 25, width: 1200, height: 775)
    let surface = RecordingAXWindows()
    surface.visibleFrames = [.primary: primary]  // no secondary attached
    surface.pidsByBundleID = ["com.microsoft.VSCode": [7]]
    surface.settablePIDs = [7]
    let capability = AXWindowCapability(surface: surface)

    #expect(try await capability.arrange(bundleID: "com.microsoft.VSCode", frame: .full, display: .secondary) == .arranged)
    #expect(surface.recordedFrames == [primary])
}

@Test("no attached display is an honest unsupported outcome, never a guessed frame")
func noDisplayIsUnsupported() async throws {
    let surface = RecordingAXWindows()
    surface.pidsByBundleID = ["com.microsoft.VSCode": [7]]
    surface.settablePIDs = [7]
    let capability = AXWindowCapability(surface: surface)

    guard case .unsupported = try await capability.arrange(bundleID: "com.microsoft.VSCode", frame: .full, display: .primary) else {
        Issue.record("Expected unsupported when no display is attached.")
        return
    }
    #expect(surface.recordedFrames.isEmpty)
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
