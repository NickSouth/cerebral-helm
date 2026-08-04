import AppKit

/// Watches for the pointer resting against the left screen edge and fires the sidebar reveal —
/// the auto-hide Dock's interaction, and the trigger the owner chose over a scroll gesture
/// (decision, 2026-08-03).
///
/// **Why polling rather than a hot-edge window or a global event monitor.**
/// A thin transparent panel with a tracking area is the obvious approach, but to receive
/// `mouseEntered` it must not be click-through — so it would swallow clicks along the very edge of
/// the screen, including in whatever fullscreen app is beneath it. A global `NSEvent` monitor
/// avoids that but its behavior depends on input-monitoring permission, which would make the
/// feature fail silently for a user who has not granted it. Sampling `NSEvent.mouseLocation`
/// needs no window, intercepts nothing, requires no permission, and reads global screen
/// coordinates so it works identically inside a fullscreen Space. The cost is one cheap timer.
///
/// The pointer must *rest* in the band, not merely cross it: without the dwell, every trip to a
/// window control near the left edge would fling the sidebar out.
final class ScreenEdgeMonitor {
    /// How close to the edge counts. Deliberately tiny — the pointer should have to actually hit
    /// the edge, the way the Dock demands.
    private static let bandWidth: CGFloat = 2

    /// How long the pointer must rest in the band before revealing. Long enough that passing
    /// through does not trigger, short enough to feel immediate. User-adjustable from settings
    /// (`SidebarEdgePreference.Dwell`).
    var dwell: TimeInterval = SidebarEdgePreference.Dwell.standard.seconds

    /// Whether the edge is armed at all. Disabling leaves the timer running but inert, so
    /// re-enabling from settings takes effect immediately with no restart.
    var isEnabled: Bool = true

    /// Dead zones at the top and bottom of the edge. The top clears the menu bar, a fullscreen
    /// app's menu-reveal strip, and the top-left hot corner; the bottom clears the bottom-left
    /// hot corner and a bottom Dock's leftmost tiles.
    private static let topInset: CGFloat = 120
    private static let bottomInset: CGFloat = 80

    /// Sampling interval. Fast enough that the dwell measurement is accurate to a frame or two.
    private static let interval: TimeInterval = 0.05

    /// Fired on the main queue when the pointer has rested in the band for `dwell`.
    var onTrigger: (() -> Void)?

    /// The display whose left edge is live. Nil disables the monitor for that tick.
    var targetScreen: (() -> NSScreen?)?

    /// Asked before every trigger — true while the sidebar is already showing, so resting at the
    /// edge does not re-fire against a panel that is already out.
    var isSuppressed: (() -> Bool)?

    /// The rect the pointer must stay inside to keep a **hover-revealed** sidebar open, or nil
    /// when nothing should auto-collapse (pinned, or summoned by the hotkey — there the pointer is
    /// wherever the user left it, usually already outside, so hover-out would close it instantly).
    var hoverFrame: (() -> NSRect?)?

    /// Fired when the pointer has been outside `hoverFrame` for `exitGrace`.
    var onExit: (() -> Void)?

    /// A brief grace before collapsing, so clipping a corner or overshooting the edge on the way
    /// to a control does not snap the column shut mid-reach.
    private static let exitGrace: TimeInterval = 0.25

    /// Slack around the panel so the pointer sitting exactly on its boundary still counts as
    /// inside — without it the sidebar collapses while the user is on its own edge.
    private static let exitSlack: CGFloat = 4

    private var exitStart: Date?

    private var timer: Timer?
    private var dwellStart: Date?
    /// Set after a trigger; the pointer must leave the band before another reveal can arm. Without
    /// it, dismissing while the pointer still sits at the edge would immediately re-reveal.
    private var awaitingExit = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        // `.common` so sampling continues during menu tracking and window drags, which otherwise
        // run their own run-loop mode and would freeze the monitor.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dwellStart = nil
        awaitingExit = false
    }

    deinit {
        timer?.invalidate()
    }

    private func sample() {
        // The hover-out collapse runs first and independently of `isEnabled`: that flag arms the
        // *reveal*, while a sidebar already on screen must still be able to tuck itself away.
        sampleHoverExit()

        guard isEnabled else {
            dwellStart = nil
            awaitingExit = false
            return
        }
        guard let screen = targetScreen?() else {
            dwellStart = nil
            return
        }
        guard Self.isEdgeReachable(of: screen) else {
            dwellStart = nil
            return
        }

        let location = NSEvent.mouseLocation
        guard Self.isInBand(location, of: screen) else {
            // Leaving the band both cancels an in-progress dwell and re-arms after a trigger.
            dwellStart = nil
            awaitingExit = false
            return
        }
        guard !awaitingExit else { return }

        // Already showing: hold the trigger, and require an exit before the next one so the
        // pointer sitting at the edge cannot fight a dismissal.
        if isSuppressed?() == true {
            dwellStart = nil
            awaitingExit = true
            return
        }

        guard let started = dwellStart else {
            dwellStart = Date()
            return
        }
        guard Date().timeIntervalSince(started) >= dwell else { return }
        dwellStart = nil
        awaitingExit = true
        onTrigger?()
    }

    /// Collapse a hover-revealed sidebar once the pointer leaves it — the standard flyout
    /// behavior, rather than waiting for a click elsewhere (owner feedback, 2026-08-03).
    private func sampleHoverExit() {
        guard let frame = hoverFrame?() else {
            // Nothing is auto-collapsing right now (hidden, pinned, or hotkey-summoned).
            exitStart = nil
            return
        }
        let inside = frame.insetBy(dx: -Self.exitSlack, dy: -Self.exitSlack).contains(NSEvent.mouseLocation)
        guard !inside else {
            exitStart = nil
            return
        }
        guard let started = exitStart else {
            exitStart = Date()
            return
        }
        guard Date().timeIntervalSince(started) >= Self.exitGrace else { return }
        exitStart = nil
        onExit?()
    }

    /// The band: within `bandWidth` of the screen's left edge, between the two dead zones.
    private static func isInBand(_ point: NSPoint, of screen: NSScreen) -> Bool {
        let frame = screen.frame
        guard point.x >= frame.minX, point.x <= frame.minX + bandWidth else { return false }
        return point.y > frame.minY + bottomInset && point.y < frame.maxY - topInset
    }

    /// False when another display sits immediately to the left of this one. That edge is a
    /// crossing point between monitors, not a wall — arming it would fire the sidebar every time
    /// the pointer travelled between displays. Such a setup simply has no reachable left edge on
    /// this screen; choosing a different display is a settings concern.
    private static func isEdgeReachable(of screen: NSScreen) -> Bool {
        let frame = screen.frame
        return !NSScreen.screens.contains { other in
            other != screen
                && other.frame.maxX <= frame.minX + 1
                && other.frame.maxY > frame.minY
                && other.frame.minY < frame.maxY
        }
    }
}
