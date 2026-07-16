#if canImport(AppKit)
import CoreGraphics
import Foundation

/// The screen strip the persistent bottom bar occupies, plus the symmetric gap a
/// foreign window must leave above it (NIC-144). Derived from the bar's on-screen
/// rect and its host screen; the window-snap observer (NIC-144 increment 2) reads
/// these to keep other apps' windows from dropping their bottom edge onto the bar.
///
/// All coordinates are AppKit screen coordinates (origin bottom-left, y up) — the
/// same space `NSScreen.frame` and the window coordinator's anchor math use. The
/// conversion from web CSS-viewport px to this space happens at the coordinator
/// seam; the geometry here stays pure so the symmetric-gap math is unit-testable.
public struct ReservedStrip: Equatable, Sendable {
    /// The full frame of the screen this strip belongs to — used to match a foreign
    /// window to the display whose bar it might be covering.
    public let screenFrame: CGRect
    /// The lowest y a window's bottom edge (its `minY`) may take. A window whose
    /// bottom drops below this intrudes on the bar and gets lifted back up to it.
    /// Equals the bar's top edge plus a gap equal to the bar's gap to the screen bottom.
    public let minWindowBottom: CGFloat

    public init(screenFrame: CGRect, minWindowBottom: CGFloat) {
        self.screenFrame = screenFrame
        self.minWindowBottom = minWindowBottom
    }

    /// Derive the reserved strip from the bar's on-screen rect (AppKit y-up) and its
    /// host screen frame. The bar sits a small gap above the screen bottom; the snap
    /// region mirrors that gap above the bar's top, so a snapped window and the screen
    /// edge leave equal space around the bar (NIC-144, symmetric-gap requirement). A
    /// bar flush to the screen bottom yields a zero gap, never a negative one.
    public static func from(barFrame: CGRect, screenFrame: CGRect) -> ReservedStrip {
        let gapBelow = max(0, barFrame.minY - screenFrame.minY)
        let reservedTop = barFrame.maxY + gapBelow
        return ReservedStrip(screenFrame: screenFrame, minWindowBottom: reservedTop)
    }
}

/// The pure geometry of keeping a foreign window off the bar (NIC-144 inc 2). Given
/// a window's AppKit-global frame and the known reserved strips, decide whether it
/// intrudes and, if so, where it should go. No AppKit, no Accessibility — the risky
/// math is isolated here so it is fully unit-testable; the observer wraps it with the
/// AX plumbing and the settle/reentrancy control flow.
public enum WindowSnapCorrection {
    /// The corrected AppKit-global frame for a window that drops its bottom edge onto
    /// the bar, or `nil` when it clears every strip and should be left untouched.
    ///
    /// The window is matched to the strip whose screen it most overlaps. A window that
    /// merely straddles the bar (its top still above the reserved line) is **shrunk** —
    /// its top edge stays put so a maximized window doesn't run off the top of the
    /// screen. A window sitting entirely inside the reserved zone is **translated** up,
    /// preserving its size, since shrinking it would drive its height to zero.
    public static func correct(frame: CGRect, strips: [ReservedStrip]) -> CGRect? {
        guard let strip = bestStrip(for: frame, among: strips) else { return nil }
        // The window's bottom edge already clears the reserved line — nothing to do.
        // Strict inequality: a window resting exactly on the line is settled, which
        // also stops a just-applied correction from re-triggering itself.
        guard frame.minY < strip.minWindowBottom else { return nil }
        let top = frame.maxY
        if top <= strip.minWindowBottom {
            // Wholly inside the reserved zone → lift it, preserving its size.
            return CGRect(x: frame.minX, y: strip.minWindowBottom, width: frame.width, height: frame.height)
        }
        // Straddling the line → pin the bottom to it and keep the top edge fixed.
        return CGRect(
            x: frame.minX, y: strip.minWindowBottom,
            width: frame.width, height: top - strip.minWindowBottom
        )
    }

    /// The strip on the display the window most overlaps — robust when a window spans
    /// two displays, and the single-strip case in inc 2 reduces to the obvious match.
    private static func bestStrip(for frame: CGRect, among strips: [ReservedStrip]) -> ReservedStrip? {
        var best: ReservedStrip?
        var bestArea: CGFloat = 0
        for strip in strips {
            let overlap = strip.screenFrame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = strip
            }
        }
        return best
    }
}
#endif
