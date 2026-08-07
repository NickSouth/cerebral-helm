// Window-snap awareness of the persistent bottom bar (NIC-144 inc 2).
#if canImport(AppKit)
import AppKit
import ApplicationServices
import Foundation

/// The seam the ``WindowSnapObserver`` drives, so its settle/reentrancy control flow
/// is unit-testable with a fake — the AppKit + Accessibility plumbing (and the
/// AX↔AppKit coordinate flip) lives entirely in the live implementation and is kept
/// out of the tested path. Frames crossing this boundary are AppKit-global (y-up), so
/// the observer and the correction math never touch Accessibility's flipped space.
public protocol WindowSnapSurface: AnyObject {
    /// Whether this process is trusted for Accessibility (no prompting).
    var isProcessTrusted: Bool { get }
    /// Start delivering foreign windows' move/resize events; `onWindowChanged` fires
    /// with the owning process id and the window's current AppKit-global frame.
    func startObserving(onWindowChanged: @escaping (pid_t, CGRect) -> Void)
    /// Stop all observation and release the underlying Accessibility observers.
    func stopObserving()
    /// Move/resize the last-reported window for `pid` to an AppKit-global frame.
    /// `false` when the app exposes no settable window (the NIC-88 reliability gate).
    func setFrame(pid: pid_t, appKitFrame: CGRect) -> Bool
}

/// Keeps other apps' windows from covering the persistent bottom bar (NIC-144): when a
/// foreign window's move/resize settles with its bottom edge dropped onto a reserved
/// strip, it is nudged back above the bar. Correction runs on **settle**, not during
/// the live drag, so it never fights the cursor; a just-applied correction is ignored
/// so it never loops. With Accessibility trust absent it is an inert no-op — never a
/// prompt (FR-SAF-07).
///
/// Main-thread confined: Accessibility notifications arrive on the main run loop and
/// the correction repositions windows, so `start`/`stop` and the internal handlers all
/// run on main. `@unchecked Sendable` documents that confinement — the state is touched
/// only on main (the AX run-loop source is the main loop; the settle hop is
/// `DispatchQueue.main`), so `self` may cross into the main-queue closure safely.
public final class WindowSnapObserver: @unchecked Sendable {
    private let surface: any WindowSnapSurface
    private let reservedStrips: () -> [ReservedStrip]
    private let settleInterval: TimeInterval

    /// Latest frame per process awaiting its settle, and whether a settle is queued.
    private var pending: [pid_t: CGRect] = [:]
    /// The queued settle per process — rescheduled on every event so correction fires
    /// only once movement has been quiet for `settleInterval` (a trailing settle), never
    /// mid-drag and never mid-fullscreen-transition.
    private var settleWork: [pid_t: DispatchWorkItem] = [:]
    /// The frame we last applied per process — the echo of our own move is ignored so
    /// the observer never chases its own correction.
    private var lastApplied: [pid_t: CGRect] = [:]
    /// Whether observation is live under Accessibility trust. `start()` is idempotent
    /// once armed; while unarmed (trust not yet granted) each call retries, so a
    /// mid-session grant — surfaced by the app reactivating — takes effect without a
    /// relaunch.
    private var isArmed = false

    /// `settleInterval`: how long window movement must be quiet before a correction is
    /// applied. `0` corrects synchronously (used by tests); the live shell debounces.
    public init(
        surface: any WindowSnapSurface,
        reservedStrips: @escaping () -> [ReservedStrip],
        settleInterval: TimeInterval = 0.12
    ) {
        self.surface = surface
        self.reservedStrips = reservedStrips
        self.settleInterval = settleInterval
    }

    /// Begin (or retry) observation. Idempotent once armed; safe to call again on app
    /// reactivation to pick up an Accessibility grant made since the last attempt.
    public func start() {
        guard !isArmed else { return }
        surface.startObserving { [weak self] pid, frame in
            self?.windowChanged(pid: pid, frame: frame)
        }
        isArmed = surface.isProcessTrusted
    }

    public func stop() {
        surface.stopObserving()
        for work in settleWork.values {
            work.cancel()
        }
        settleWork.removeAll()
        pending.removeAll()
        lastApplied.removeAll()
        isArmed = false
    }

    private func windowChanged(pid: pid_t, frame: CGRect) {
        guard surface.isProcessTrusted else { return }
        pending[pid] = frame
        if settleInterval <= 0 {
            settle(pid: pid)
            return
        }
        // Trailing settle: each event cancels the prior deadline and starts a new one,
        // so a burst of drag/animation events collapses into one correction after it
        // stops — by which point a window entering fullscreen has finished the transition.
        settleWork[pid]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settleWork[pid] = nil
            self?.settle(pid: pid)
        }
        settleWork[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval, execute: work)
    }

    private func settle(pid: pid_t) {
        guard let frame = pending.removeValue(forKey: pid) else { return }
        // Our own just-applied correction echoing back as a move — swallow it once.
        if let applied = lastApplied[pid], applied.approximatelyEqual(to: frame) {
            lastApplied[pid] = nil
            return
        }
        guard let corrected = WindowSnapCorrection.correct(frame: frame, strips: reservedStrips()) else {
            return
        }
        if surface.setFrame(pid: pid, appKitFrame: corrected) {
            lastApplied[pid] = corrected
        }
    }
}

private extension CGRect {
    /// AppKit hands back exactly what we set, but guard the equality against sub-point
    /// rounding so the echo-suppression never misses by a hair.
    func approximatelyEqual(to other: CGRect, epsilon: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) < epsilon && abs(minY - other.minY) < epsilon
            && abs(width - other.width) < epsilon && abs(height - other.height) < epsilon
    }
}

/// Live Accessibility surface for ``WindowSnapObserver``. Observes each regular running
/// app's windows (except our own) for move/resize/create, converts frames from
/// Accessibility's top-left space to AppKit-global, and applies corrections back.
/// Explicitly full-screen windows (fullscreen video and the like) are excluded so they
/// keep covering the bar — checked on report and re-checked before any move. Regular
/// apps launched while running are picked up (and quit apps dropped) via NSWorkspace, so
/// coverage isn't limited to the apps present at startup.
///
/// `@unchecked Sendable`: all state is touched on the main thread — the AX run-loop
/// source is the main loop and the NSWorkspace notifications post on the main queue.
public final class SystemWindowSnapSurface: WindowSnapSurface, @unchecked Sendable {
    /// Per-observed-process context handed to the C callback as its refcon.
    private final class AppContext {
        let pid: pid_t
        weak var surface: SystemWindowSnapSurface?
        init(pid: pid_t, surface: SystemWindowSnapSurface) {
            self.pid = pid
            self.surface = surface
        }
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var contexts: [pid_t: AppContext] = [:]
    /// The last window element reported for a process — the element a correction moves,
    /// so we reposition the very window that shifted, not merely "a main window".
    private var lastWindow: [pid_t: AXUIElement] = [:]
    /// NSWorkspace launch/terminate subscriptions, released on stop.
    private var workspaceObservers: [NSObjectProtocol] = []
    private var onWindowChanged: ((pid_t, CGRect) -> Void)?

    public init() {}

    public var isProcessTrusted: Bool { AXIsProcessTrusted() }

    /// Primary display height in AppKit points — the pivot for the AX↔AppKit y-flip.
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    public func startObserving(onWindowChanged: @escaping (pid_t, CGRect) -> Void) {
        self.onWindowChanged = onWindowChanged
        guard isProcessTrusted else { return }
        for app in NSWorkspace.shared.runningApplications where isManageable(app) {
            attach(pid: app.processIdentifier)
        }
        registerWorkspaceObserversIfNeeded()
    }

    public func stopObserving() {
        for observer in observers.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
            )
        }
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
        observers.removeAll()
        contexts.removeAll()
        lastWindow.removeAll()
        onWindowChanged = nil
    }

    /// A regular (Dock-visible) app other than ourselves — the only windows worth
    /// managing; agents, our own backdrop, and background helpers are skipped.
    private func isManageable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    /// Track apps launched/quit while running so coverage follows the live app set, not
    /// just the snapshot at startup. Registered once; the tokens are released on stop.
    private func registerWorkspaceObserversIfNeeded() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                self.isManageable(app)
            else { return }
            self.attach(pid: app.processIdentifier)
        }
        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.detach(pid: app.processIdentifier)
        }
        workspaceObservers = [launched, terminated]
    }

    public func setFrame(pid: pid_t, appKitFrame: CGRect) -> Bool {
        guard let window = lastWindow[pid] else { return false }
        // A window that reached native fullscreen after we queued the correction must be
        // left alone (re-checked here to cover the enter-fullscreen animation race).
        if isFullScreen(window) { return false }
        // AppKit-global (y-up) → Accessibility (top-left, y-down): the window's AppKit
        // top edge becomes its AX origin y, measured down from the primary's top.
        var origin = CGPoint(x: appKitFrame.minX, y: primaryHeight - appKitFrame.maxY)
        var size = CGSize(width: appKitFrame.width, height: appKitFrame.height)
        guard
            let position = AXValueCreate(.cgPoint, &origin),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success && sized == .success
    }

    // MARK: - Accessibility wiring

    private static let callback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let context = Unmanaged<AppContext>.fromOpaque(refcon).takeUnretainedValue()
        context.surface?.handleWindowNotification(pid: context.pid, element: element)
    }

    private func attach(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &observer) == .success, let observer else { return }

        let context = AppContext(pid: pid, surface: self)
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        let application = AXUIElementCreateApplication(pid)

        // New windows within an already-observed app get their own move/resize hooks.
        AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, refcon)
        for window in windows(of: application) {
            addWindowNotifications(observer, window, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        contexts[pid] = context
    }

    /// A quit app's observer is torn down so its run-loop source and context don't leak.
    private func detach(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
        contexts[pid] = nil
        lastWindow[pid] = nil
    }

    private func addWindowNotifications(_ observer: AXObserver, _ window: AXUIElement, _ refcon: UnsafeMutableRawPointer) {
        AXObserverAddNotification(observer, window, kAXWindowMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, window, kAXWindowResizedNotification as CFString, refcon)
    }

    private func windows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    /// A window moved, resized, or was created. Record it as this process's active
    /// window, read its live frame, and hand the AppKit-global rect to the observer.
    private func handleWindowNotification(pid: pid_t, element: AXUIElement) {
        // A freshly created window arrives here via the app element's created-notification;
        // start tracking its own moves too, then report its current frame.
        if let observer = observers[pid], let context = contexts[pid] {
            addWindowNotifications(observer, element, Unmanaged.passUnretained(context).toOpaque())
        }
        // Never manage an explicitly full-screen window (NIC-144): fullscreen video and
        // the like must be allowed to cover the bar. Native fullscreen is authoritative
        // via the AXFullScreen attribute; such a window also lives on its own Space.
        if isFullScreen(element) { return }
        lastWindow[pid] = element
        guard let axFrame = frame(of: element) else { return }
        // Accessibility (top-left, y-down) → AppKit-global (y-up).
        let appKit = CGRect(
            x: axFrame.minX, y: primaryHeight - axFrame.maxY,
            width: axFrame.width, height: axFrame.height
        )
        onWindowChanged?(pid, appKit)
    }

    /// Whether the window is in native macOS fullscreen. `AXFullScreen` is not a public
    /// constant but is the attribute the window server exposes (and window managers rely
    /// on); a window that doesn't expose it is treated as not fullscreen.
    private func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success,
            let number = value as? NSNumber
        else { return false }
        return number.boolValue
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue, let sizeValue
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(unsafeDowncast(positionValue as AnyObject, to: AXValue.self), .cgPoint, &origin),
            AXValueGetValue(unsafeDowncast(sizeValue as AnyObject, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
#endif
