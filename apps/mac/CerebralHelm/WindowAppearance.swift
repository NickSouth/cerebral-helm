import AppKit

/// How CerebralHelm's summoned windows arrive and leave (2026-08-07).
///
/// Until now no window in the app had a show animation at all — Settings, More Apps and the Window
/// Navigator each snapped into existence at full size and full opacity. That reads as a glitch
/// rather than as an opening, and it is the last thing between these surfaces and the look the
/// mockups set.
///
/// This could not be built earlier. Inside an opaque window a fade only fades the *contents*, so
/// the box still snaps in around them and the animation makes things worse by drawing attention to
/// the snap. `VibrantWindowChrome` removed the box; this is what that unblocked.
///
/// **Fade plus travel, not scale.** The surfaces travel a short distance out of whatever the user
/// clicked and fade up as they go, which is the same grammar macOS uses for popovers. Scaling was
/// the tempting alternative — the in-page settings overlay does exactly that in CSS — but a window
/// cannot be scaled: the only lever is its frame, and animating that re-lays-out the web content
/// every frame, so text re-wraps its way to the final size instead of growing. Travel keeps the
/// layout fixed for the whole animation, so nothing reflows.
///
/// The direction carries the meaning. A surface that emerges from the control that summoned it
/// explains where it came from and where it will go back to; the anchor is what makes the motion
/// informative rather than decorative.
enum WindowAppearance {
    /// Aligned with the web scale in `tokens.css`: `--ch-motion-fast` (120ms) and
    /// `--ch-motion-base` (200ms). Opening is the one the eye follows, so it gets the longer beat;
    /// dismissal should be out of the way before it is thought about.
    static let openDuration: TimeInterval = 0.20
    static let closeDuration: TimeInterval = 0.12

    /// How far the window travels. Far enough to read as movement, short enough that the surface is
    /// never meaningfully misplaced while it arrives — the user is already looking where they
    /// clicked, and a long flight would make them wait for it to land.
    static let travel: CGFloat = 18

    /// macOS's own reduce-motion setting. The app honours it everywhere else through the CSS
    /// tokens, which native code cannot read, so it is asked directly here.
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Show `window` at the frame it has already been positioned at, arriving from `anchor`.
    ///
    /// Callers position first and present second — `window.frame` at this point IS the destination,
    /// so the offset is applied and then animated away rather than the caller having to compute two
    /// frames. `anchor` is a point in screen coordinates, normally the centre of the control that
    /// was clicked; `nil` falls back to a straight rise, which is what a surface with no
    /// summoning control (a hotkey, a menu item) should do.
    static func present(_ window: NSWindow, emergingFrom anchor: NSPoint? = nil) {
        let destination = window.frame

        guard !reduceMotion else {
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            return
        }

        window.alphaValue = 0
        window.setFrame(offset(destination, toward: anchor), display: false)
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = openDuration
            // Decelerating: fast out of the control, settling into place. `.easeOut` is the curve
            // the CSS `--ch-ease-standard` approximates.
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(destination, display: true)
        }
    }

    /// Fade `window` back toward `anchor` and then run `completion`, which is where the caller
    /// actually orders it out.
    ///
    /// The window is captured strongly by the animation, so a controller released the moment it
    /// asks to close cannot take the window down mid-flight.
    static func dismiss(
        _ window: NSWindow,
        receding toward: NSPoint? = nil,
        completion: @escaping () -> Void
    ) {
        guard !reduceMotion else {
            completion()
            window.alphaValue = 1
            return
        }

        let origin = window.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(offset(origin, toward: toward), display: true)
        } completionHandler: {
            completion()
            // Restore both, or a warm-reused window (Settings) would reopen invisible and in the
            // wrong place. `present` re-applies its own offset from the caller's fresh position.
            window.alphaValue = 1
            window.setFrame(origin, display: false)
        }
    }

    /// `frame` nudged `travel` points toward `anchor`, or straight down when there is no anchor.
    ///
    /// The offset is a fixed distance along the direction to the anchor, not a fraction of the
    /// distance: a launcher opening right beside its button and a window opening across a 6K
    /// display should travel the same visible amount.
    private static func offset(_ frame: NSRect, toward anchor: NSPoint?) -> NSRect {
        var moved = frame
        guard let anchor else {
            // No anchor: rise into place. Down-then-up is the neutral "appeared" gesture, and it
            // never implies a direction the surface did not actually come from.
            moved.origin.y -= travel
            return moved
        }

        let dx = anchor.x - frame.midX
        let dy = anchor.y - frame.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        // The anchor sits under the window's own centre (a surface opening exactly where it was
        // summoned). There is no direction to travel along, so fall back to the neutral rise.
        guard distance > 1 else {
            moved.origin.y -= travel
            return moved
        }

        moved.origin.x += dx / distance * travel
        moved.origin.y += dy / distance * travel
        return moved
    }
}
