import Foundation
import CerebralCore

/// Pure named-frame geometry (NIC-142): the single source of the frame→rect math
/// the AX adapter arranges with and the layout-capture path snaps to. Coordinate
/// space is the caller's (the AX adapter passes Accessibility top-left rects); the
/// math is relative to the given visible area, so it holds in any space.
public enum WindowFrameGeometry {
    /// The rect a named frame occupies within a display's visible area.
    public static func resolve(_ frame: WindowFrame, in visible: WindowRect) -> WindowRect {
        let x = visible.x, y = visible.y, w = visible.width, h = visible.height
        switch frame {
        case .full:
            return visible
        case .leftHalf:
            return WindowRect(x: x, y: y, width: w / 2, height: h)
        case .rightHalf:
            return WindowRect(x: x + w / 2, y: y, width: w / 2, height: h)
        case .topHalf:
            return WindowRect(x: x, y: y, width: w, height: h / 2)
        case .bottomHalf:
            return WindowRect(x: x, y: y + h / 2, width: w, height: h / 2)
        case .leftTwoThirds:
            return WindowRect(x: x, y: y, width: w * 2 / 3, height: h)
        case .rightThird:
            return WindowRect(x: x + w * 2 / 3, y: y, width: w / 3, height: h)
        case .centered:
            return WindowRect(x: x + w / 8, y: y + h / 8, width: w * 3 / 4, height: h * 3 / 4)
        }
    }

    /// The named frame a captured window rect most closely occupies within the
    /// visible area, by intersection-over-union (NIC-142 live capture). Ties break
    /// deterministically by the frame enum's declaration order.
    public static func snap(_ rect: WindowRect, in visible: WindowRect) -> WindowFrame {
        var best = WindowFrame.full
        var bestScore = -1.0
        for frame in WindowFrame.allCases {
            let score = intersectionOverUnion(rect, resolve(frame, in: visible))
            if score > bestScore {
                bestScore = score
                best = frame
            }
        }
        return best
    }

    static func intersectionOverUnion(_ a: WindowRect, _ b: WindowRect) -> Double {
        let ix = max(a.x, b.x)
        let iy = max(a.y, b.y)
        let iMaxX = min(a.x + a.width, b.x + b.width)
        let iMaxY = min(a.y + a.height, b.y + b.height)
        let iw = iMaxX - ix
        let ih = iMaxY - iy
        guard iw > 0, ih > 0 else { return 0 }
        let intersection = iw * ih
        let union = a.width * a.height + b.width * b.height - intersection
        return union > 0 ? intersection / union : 0
    }
}
