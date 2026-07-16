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
        // Cross-display moves are flaky with a single position+size write: the window
        // lands on the target display but keeps its old size (the size is clamped
        // against the origin display before the move settles) — the symptom is "moved
        // to the right monitor but not sized to its frame". Set position → size →
        // position → size so the final size is applied on the destination display (the
        // Rectangle/Magnet idiom); the last two calls decide success.
        _ = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, position)
        _ = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
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
        if AXUIElementCopyAttributeValue(application, kAXMainWindowAttribute as CFString, &windowValue) == .success,
           let window = windowValue {
            // A CFTypeRef from the main-window attribute is an AXUIElement by contract.
            return unsafeDowncast(window as AnyObject, to: AXUIElement.self)
        }
        // Fall back to the app's first window: some apps never set a main window, and a
        // just-launched app may not have one yet — arrange should still target a real
        // window rather than silently no-op (the layout arrange, NIC-142).
        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AnyObject], let first = windows.first {
            return unsafeDowncast(first, to: AXUIElement.self)
        }
        return nil
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
    /// The reserved bottom-bar strips (NIC-142/144): an arranged window is kept above
    /// the persistent bottom bar so it lands correctly the first time, rather than
    /// overlapping and being nudged up afterwards by the window-snap observer.
    private let reservedStrips: @Sendable () -> [ReservedStrip]

    public init(
        surface: any AXWindowSurface = SystemAXWindows(),
        layoutDisplay: @escaping @Sendable () -> WindowDisplay? = { nil },
        reservedStrips: @escaping @Sendable () -> [ReservedStrip] = { [] }
    ) {
        self.surface = surface
        self.layoutDisplay = layoutDisplay
        self.reservedStrips = reservedStrips
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
        let rect = Self.reserveBottomBar(Self.resolve(frame, in: visible), strips: reservedStrips())
        return apply(rect, bundleID: bundleID)
    }

    /// Keep an arranged AX-space rect above the persistent bottom bar (NIC-142) by
    /// running it through the same `WindowSnapCorrection` the snap observer uses — so
    /// the window fits above the bar on the first placement, with no post-arrange jump.
    /// Round-trips through AppKit-global coordinates (the space the correction speaks).
    static func reserveBottomBar(_ axRect: CGRect, strips: [ReservedStrip]) -> CGRect {
        guard !strips.isEmpty, let primaryHeight = NSScreen.screens.first?.frame.height else { return axRect }
        // AX top-left → AppKit bottom-left (y flips about the primary display height).
        let appKit = CGRect(x: axRect.minX, y: primaryHeight - axRect.maxY, width: axRect.width, height: axRect.height)
        guard let corrected = WindowSnapCorrection.correct(frame: appKit, strips: strips) else { return axRect }
        return CGRect(
            x: corrected.minX, y: primaryHeight - corrected.maxY,
            width: corrected.width, height: corrected.height
        )
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
