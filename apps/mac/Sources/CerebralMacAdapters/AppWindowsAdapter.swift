#if canImport(AppKit)
import AppKit
import ApplicationServices
import CerebralTools

/// Private Accessibility SPI: maps an `AXUIElement` window to its `CGWindowID` — the
/// stable, cross-call window identity the navigator addresses (owner decision, NIC-143).
/// There is no public API for this; `_AXUIElementGetWindow` is the long-standing
/// (Rectangle/yabai/Hammerspoon) approach. Isolated here so the private-symbol
/// dependency has one home.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// One regular running application, for window enumeration.
public struct AXAppProcess: Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String
    public let appName: String
    /// The app's icon as a base64 PNG for the navigator card mark; `nil` when it
    /// cannot be rendered.
    public let iconPNGBase64: String?
    public init(pid: pid_t, bundleID: String, appName: String, iconPNGBase64: String? = nil) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.iconPNGBase64 = iconPNGBase64
    }
}

/// One enumerated window (NIC-143): its `CGWindowID`, owning process, title, and
/// minimized state.
public struct AXWindowRecord: Equatable, Sendable {
    public let windowID: UInt32
    public let pid: pid_t
    public let title: String
    public let minimized: Bool
    public init(windowID: UInt32, pid: pid_t, title: String, minimized: Bool) {
        self.windowID = windowID
        self.pid = pid
        self.title = title
        self.minimized = minimized
    }
}

/// The seam over the Accessibility window surface for the navigator, so the
/// capability's grouping and id-resolution logic is testable with a fake (the same
/// pattern as ``AXWindowSurface``). Actions are addressed by `(windowID, pid)`; the
/// live surface re-resolves the AX element for that id at call time.
public protocol AppWindowsSurface: Sendable {
    /// Whether this process is trusted for Accessibility control (never prompts).
    var isProcessTrusted: Bool { get }
    /// Regular (Dock-visible) running applications, excluding the host.
    func regularApplications() -> [AXAppProcess]
    /// The windows of a process (those that expose a `CGWindowID`).
    func windows(pid: pid_t) -> [AXWindowRecord]
    /// Set a window's minimized state; returns success.
    func setMinimized(_ minimized: Bool, windowID: UInt32, pid: pid_t) -> Bool
    /// Raise the window to the front and activate its application; returns success.
    func raise(windowID: UInt32, pid: pid_t) -> Bool
    /// Close the window via its close button; returns success.
    func close(windowID: UInt32, pid: pid_t) -> Bool
}

/// Live Accessibility surface over `AXUIElement`.
public struct SystemAppWindows: AppWindowsSurface {
    public init() {}

    public var isProcessTrusted: Bool { AXIsProcessTrusted() }

    public func regularApplications() -> [AXAppProcess] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, bundleID != own else { return nil }
            return AXAppProcess(
                pid: app.processIdentifier,
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                iconPNGBase64: Self.iconBase64(app.icon)
            )
        }
    }

    /// An `NSImage` (a running app's icon) as a 64px base64 PNG for the navigator
    /// card; `nil` when it cannot be rendered.
    private static func iconBase64(_ image: NSImage?) -> String? {
        guard let image else { return nil }
        let pixels = 64
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        context.flushGraphics()
        return bitmap.representation(using: .png, properties: [:])?.base64EncodedString()
    }

    public func windows(pid: pid_t) -> [AXWindowRecord] {
        windowElements(pid: pid).compactMap { element in
            guard let windowID = Self.windowID(of: element) else { return nil }
            return AXWindowRecord(
                windowID: windowID,
                pid: pid,
                title: Self.stringAttribute(element, kAXTitleAttribute) ?? "",
                minimized: Self.boolAttribute(element, kAXMinimizedAttribute) ?? false
            )
        }
    }

    public func setMinimized(_ minimized: Bool, windowID: UInt32, pid: pid_t) -> Bool {
        guard let element = element(windowID: windowID, pid: pid) else { return false }
        let value: CFTypeRef = minimized ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value) == .success
    }

    public func raise(windowID: UInt32, pid: pid_t) -> Bool {
        guard let element = element(windowID: windowID, pid: pid) else { return false }
        // Un-minimize first so a minimized window can come forward, then raise it and
        // activate the owning app so it lands above other apps' windows.
        _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
        NSRunningApplication(processIdentifier: pid)?.activate()
        return raised
    }

    public func close(windowID: UInt32, pid: pid_t) -> Bool {
        guard let element = element(windowID: windowID, pid: pid) else { return false }
        var buttonValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &buttonValue) == .success,
              let button = buttonValue else { return false }
        let buttonElement = unsafeDowncast(button as AnyObject, to: AXUIElement.self)
        return AXUIElementPerformAction(buttonElement, kAXPressAction as CFString) == .success
    }

    // MARK: - AX helpers

    private func windowElements(pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AnyObject] else { return [] }
        return windows.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    /// Re-resolve the AX element for a window id by scanning the app's windows. The
    /// element is transient (not stable across calls), so every action re-resolves.
    private func element(windowID: UInt32, pid: pid_t) -> AXUIElement? {
        windowElements(pid: pid).first { Self.windowID(of: $0) == windowID }
    }

    private static func windowID(of element: AXUIElement) -> UInt32? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}

/// Native ``AppWindowsCapability`` (NIC-143): the window navigator's per-window
/// enumeration and actions through Accessibility, behind the process-level trust
/// check. Denied permission is a capability error, never a prompt (FR-SAF-07); an
/// unknown window id is an honest `false`. Enumeration groups each app's windows and
/// drops apps that expose none; the opaque id the UI holds is the window's
/// `CGWindowID`, stringified.
public struct MacAppWindowsCapability: AppWindowsCapability {
    private let surface: any AppWindowsSurface

    public init(surface: any AppWindowsSurface = SystemAppWindows()) {
        self.surface = surface
    }

    public func listWindows() async throws -> [AppWindowGroup] {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        return surface.regularApplications().compactMap { app in
            let windows = surface.windows(pid: app.pid).map {
                AppWindowInfo(id: String($0.windowID), title: $0.title, minimized: $0.minimized)
            }
            guard !windows.isEmpty else { return nil }
            return AppWindowGroup(
                bundleID: app.bundleID, appName: app.appName,
                appIconPNGBase64: app.iconPNGBase64, windows: windows
            )
        }
    }

    public func minimize(windowID: String) async throws -> Bool {
        try act(windowID) { surface.setMinimized(true, windowID: $0, pid: $1) }
    }

    public func surface(windowID: String) async throws -> Bool {
        try act(windowID) { surface.raise(windowID: $0, pid: $1) }
    }

    public func close(windowID: String) async throws -> Bool {
        try act(windowID) { surface.close(windowID: $0, pid: $1) }
    }

    /// Resolve the owning process for an opaque window id (via a fresh enumeration),
    /// then run the action. Denied permission throws; an unknown or non-numeric id is
    /// a `false` result, never an error.
    private func act(_ id: String, _ perform: (UInt32, pid_t) -> Bool) throws -> Bool {
        guard surface.isProcessTrusted else { throw NativeCapabilityError.permissionDenied }
        guard let windowID = UInt32(id) else { return false }
        for app in surface.regularApplications() where surface.windows(pid: app.pid).contains(where: { $0.windowID == windowID }) {
            return perform(windowID, app.pid)
        }
        return false
    }
}
#endif
