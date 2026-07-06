#if canImport(AppKit)
import AppKit
import ApplicationServices
import CerebralTools

/// The seam over the Accessibility window surface, so frame math and outcome
/// semantics are testable with a fake (same pattern as ``WorkspaceOpening``).
///
/// Coordinates are Accessibility coordinates: origin at the primary display's
/// top-left, y growing downward — the live implementation converts from AppKit's
/// bottom-left `visibleFrame` so the capability's math stays coordinate-honest.
public protocol AXWindowSurface: Sendable {
    /// Whether this process is trusted for Accessibility control (no prompting).
    var isProcessTrusted: Bool { get }
    /// The primary display's visible area in Accessibility (top-left) coordinates,
    /// or `nil` when no display is attached.
    var primaryVisibleFrame: CGRect? { get }
    /// Process ids of running applications with the bundle id.
    func runningProcessIDs(bundleID: String) -> [pid_t]
    /// Set the application's main window frame. `false` when the application
    /// exposes no settable main window (the NIC-88 reliability gate).
    func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool
}

/// Live Accessibility surface over `AXUIElement`.
public struct SystemAXWindows: AXWindowSurface {
    public init() {}

    public var isProcessTrusted: Bool { AXIsProcessTrusted() }

    public var primaryVisibleFrame: CGRect? {
        // The primary screen is the first in `screens` (origin of the global
        // AppKit space). Convert its bottom-left visibleFrame to AX top-left.
        guard let primary = NSScreen.screens.first else { return nil }
        let visible = primary.visibleFrame
        let topLeftY = primary.frame.height - visible.maxY
        return CGRect(x: visible.minX, y: topLeftY, width: visible.width, height: visible.height)
    }

    public func runningProcessIDs(bundleID: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)
    }

    public func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue) == .success,
            let window = windowValue
        else { return false }
        // A CFTypeRef from the main-window attribute is an AXUIElement by contract.
        let axWindow = unsafeDowncast(window as AnyObject, to: AXUIElement.self)

        var origin = frame.origin
        var size = frame.size
        guard
            let position = AXValueCreate(.cgPoint, &origin),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }
        let movedResult = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, position)
        let sizedResult = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        return movedResult == .success && sizedResult == .success
    }
}

/// Native ``WindowCapability`` (NIC-88): named-frame arrangement of configured
/// applications' main windows through Accessibility, behind the process-level
/// trust check. Denied permission is a capability error with guidance, never a
/// prompt (FR-SAF-07); an application with no settable main window is an honest
/// `unsupported` partial.
public struct AXWindowCapability: WindowCapability {
    private let surface: any AXWindowSurface

    public init(surface: any AXWindowSurface = SystemAXWindows()) {
        self.surface = surface
    }

    public func inspect() async throws -> [WindowInfo] {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        return []
    }

    public func arrange(bundleID: String, frame: WindowFrame) async throws -> WindowArrangeOutcome {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        guard let visible = surface.primaryVisibleFrame else {
            return .unsupported("No display is available to arrange on.")
        }
        let pids = surface.runningProcessIDs(bundleID: bundleID)
        guard !pids.isEmpty else { return .notRunning }

        let target = Self.resolve(frame, in: visible)
        let arranged = pids.contains { surface.setMainWindowFrame(pid: $0, frame: target) }
        return arranged
            ? .arranged
            : .unsupported("The application exposes no controllable main window.")
    }

    /// Deterministic named-frame geometry within the visible area (AX top-left
    /// coordinates). Exposed for tests.
    public static func resolve(_ frame: WindowFrame, in visible: CGRect) -> CGRect {
        let width = visible.width
        let height = visible.height
        switch frame {
        case .full:
            return visible
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: width / 2, height: height)
        case .rightHalf:
            return CGRect(x: visible.minX + width / 2, y: visible.minY, width: width / 2, height: height)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: width, height: height / 2)
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY + height / 2, width: width, height: height / 2)
        case .leftTwoThirds:
            return CGRect(x: visible.minX, y: visible.minY, width: width * 2 / 3, height: height)
        case .rightThird:
            return CGRect(x: visible.minX + width * 2 / 3, y: visible.minY, width: width / 3, height: height)
        case .centered:
            return CGRect(
                x: visible.minX + width / 8, y: visible.minY + height / 8,
                width: width * 3 / 4, height: height * 3 / 4
            )
        }
    }
}
#endif
