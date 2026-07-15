#if canImport(AppKit)
import AppKit
import ApplicationServices
import CerebralCore
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
    /// The chosen display's visible area in Accessibility (top-left) coordinates.
    /// `nil` when that display is not attached (e.g. `secondary` with a single
    /// display) or no display is attached at all — the caller decides how to
    /// degrade.
    func visibleFrame(for display: WindowDisplay) -> CGRect?
    /// Process ids of running applications with the bundle id.
    func runningProcessIDs(bundleID: String) -> [pid_t]
    /// Set the application's main window frame. `false` when the application
    /// exposes no settable main window (the NIC-88 reliability gate).
    func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool
    /// Read the application's main window frame, or `nil` when it exposes none.
    func mainWindowFrame(pid: pid_t) -> CGRect?
}

/// Live Accessibility surface over `AXUIElement`.
public struct SystemAXWindows: AXWindowSurface {
    public init() {}

    public var isProcessTrusted: Bool { AXIsProcessTrusted() }

    public func visibleFrame(for display: WindowDisplay) -> CGRect? {
        // The primary screen is the first in `screens` — the origin of both the
        // global AppKit space (bottom-left, y up) and the Accessibility space
        // (top-left, y down). "secondary" is the first non-primary screen.
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let target: NSScreen?
        switch display {
        case .primary:
            target = primary
        case .secondary:
            target = screens.count > 1 ? screens[1] : nil
        }
        guard let screen = target else { return nil }

        // Convert the chosen screen's global bottom-left visibleFrame to the
        // Accessibility top-left space: x is shared across both spaces; y flips
        // about the primary display's height, so a secondary screen offset above
        // or beside the primary lands at the correct AX origin.
        let visible = screen.visibleFrame
        let topLeftY = primary.frame.height - visible.maxY
        return CGRect(x: visible.minX, y: topLeftY, width: visible.width, height: visible.height)
    }

    public func runningProcessIDs(bundleID: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)
    }

    public func setMainWindowFrame(pid: pid_t, frame: CGRect) -> Bool {
        guard let axWindow = mainWindow(pid: pid) else { return false }
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

    public func mainWindowFrame(pid: pid_t) -> CGRect? {
        guard let axWindow = mainWindow(pid: pid) else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let position = positionValue, let size = sizeValue
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        let positionAX = unsafeDowncast(position as AnyObject, to: AXValue.self)
        let sizeAX = unsafeDowncast(size as AnyObject, to: AXValue.self)
        guard
            AXValueGetValue(positionAX, .cgPoint, &origin),
            AXValueGetValue(sizeAX, .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func mainWindow(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue) == .success,
            let window = windowValue
        else { return nil }
        // A CFTypeRef from the main-window attribute is an AXUIElement by contract.
        return unsafeDowncast(window as AnyObject, to: AXUIElement.self)
    }
}

/// Native ``WindowCapability`` (NIC-88): named-frame arrangement of configured
/// applications' main windows through Accessibility, behind the process-level
/// trust check. Denied permission is a capability error with guidance, never a
/// prompt (FR-SAF-07); an application with no settable main window is an honest
/// `unsupported` partial.
public struct AXWindowCapability: WindowCapability {
    private let surface: any AXWindowSurface
    /// Resolves the display a *layout* arrange targets from the "Layout display"
    /// setting (NIC-142). `window.arrange` is used only by the synthesized layout
    /// workflow, so when this returns a display it overrides the workflow's baked
    /// (now vestigial) primary/secondary; `nil` keeps the requested display.
    private let layoutDisplay: @Sendable () -> WindowDisplay?

    public init(
        surface: any AXWindowSurface = SystemAXWindows(),
        layoutDisplay: @escaping @Sendable () -> WindowDisplay? = { nil }
    ) {
        self.surface = surface
        self.layoutDisplay = layoutDisplay
    }

    public func inspect() async throws -> [WindowInfo] {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        return []
    }

    public func arrange(bundleID: String, frame: WindowFrame, display: WindowDisplay) async throws -> WindowArrangeOutcome {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        // The "Layout display" setting governs where a layout opens (NIC-142); it
        // overrides the workflow's baked display when set.
        let target = layoutDisplay() ?? display
        // Target the requested display, degrading to the primary when the
        // secondary is absent (stranded-window pattern) so a layout authored for a
        // now-disconnected display still arranges rather than silently failing.
        guard let visible = surface.visibleFrame(for: target) ?? surface.visibleFrame(for: .primary) else {
            return .unsupported("No display is available to arrange on.")
        }
        return apply(Self.resolve(frame, in: visible), bundleID: bundleID)
    }

    public func captureFrame(bundleID: String) async throws -> WindowRect? {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        for pid in surface.runningProcessIDs(bundleID: bundleID) {
            if let frame = surface.mainWindowFrame(pid: pid) {
                return WindowRect(
                    x: frame.origin.x, y: frame.origin.y,
                    width: frame.width, height: frame.height
                )
            }
        }
        return nil
    }

    public func restoreFrame(bundleID: String, rect: WindowRect) async throws -> WindowArrangeOutcome {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        return apply(
            CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
            bundleID: bundleID
        )
    }

    public func visibleFrame() async throws -> WindowRect? {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        guard let visible = surface.visibleFrame(for: .primary) else { return nil }
        return WindowRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
    }

    private func apply(_ target: CGRect, bundleID: String) -> WindowArrangeOutcome {
        let pids = surface.runningProcessIDs(bundleID: bundleID)
        guard !pids.isEmpty else { return .notRunning }
        let arranged = pids.contains { surface.setMainWindowFrame(pid: $0, frame: target) }
        return arranged
            ? .arranged
            : .unsupported("The application exposes no controllable main window.")
    }

    /// Deterministic named-frame geometry within the visible area (AX top-left
    /// coordinates), delegating to the portable ``WindowFrameGeometry`` — the single
    /// source shared with the layout-capture snap path (NIC-142). Exposed for tests.
    public static func resolve(_ frame: WindowFrame, in visible: CGRect) -> CGRect {
        let rect = WindowFrameGeometry.resolve(
            frame,
            in: WindowRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        )
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
#endif
