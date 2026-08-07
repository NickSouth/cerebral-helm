import Foundation
import Testing
import CerebralCore
import CerebralTools

// NIC-142: the portable named-frame geometry shared by window.arrange and the
// layout-capture snap path.

@Test("resolve produces the named-frame rect within the visible area")
func resolveNamedFrames() {
    let visible = WindowRect(x: 0, y: 0, width: 1200, height: 900)
    #expect(WindowFrameGeometry.resolve(.full, in: visible) == visible)
    #expect(WindowFrameGeometry.resolve(.leftHalf, in: visible) == WindowRect(x: 0, y: 0, width: 600, height: 900))
    #expect(WindowFrameGeometry.resolve(.rightThird, in: visible) == WindowRect(x: 800, y: 0, width: 400, height: 900))
    #expect(WindowFrameGeometry.resolve(.leftTwoThirds, in: visible) == WindowRect(x: 0, y: 0, width: 800, height: 900))
}

@Test("snap picks the named frame a captured window most occupies")
func snapPicksNearestFrame() {
    let visible = WindowRect(x: 0, y: 0, width: 1200, height: 800)
    #expect(WindowFrameGeometry.snap(WindowRect(x: 0, y: 0, width: 800, height: 800), in: visible) == .leftTwoThirds)
    #expect(WindowFrameGeometry.snap(WindowRect(x: 810, y: 5, width: 380, height: 790), in: visible) == .rightThird)
    #expect(WindowFrameGeometry.snap(WindowRect(x: 10, y: 10, width: 1180, height: 780), in: visible) == .full)
    #expect(WindowFrameGeometry.snap(WindowRect(x: 0, y: 0, width: 600, height: 800), in: visible) == .leftHalf)
}
