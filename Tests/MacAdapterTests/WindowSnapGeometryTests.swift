#if canImport(AppKit)
import CoreGraphics
import Testing

import CerebralMacAdapters

/// Reserved bottom-bar strip geometry (NIC-144 inc 1): the snap region mirrors the
/// bar's gap to the screen bottom above the bar, so a snapped window and the screen
/// edge leave equal space around it.

@Test("the reserved strip leaves a gap above the bar equal to its gap below")
func reservedStripIsSymmetric() {
    // Primary screen 1440 tall; the bar (36 tall) sits 12 above the bottom.
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let bar = CGRect(x: 20, y: 12, width: 2520, height: 36)

    let strip = ReservedStrip.from(barFrame: bar, screenFrame: screen)

    // Gap below = 12; window bottoms must clear the bar top (48) by that same 12.
    #expect(strip.minWindowBottom == 60)
    #expect(strip.screenFrame == screen)
}

@Test("a secondary display's strip is expressed in that screen's global coordinates")
func reservedStripHonorsScreenOrigin() {
    // A screen offset above the primary (global y-up origin at 1440).
    let screen = CGRect(x: 0, y: 1440, width: 1920, height: 1080)
    let bar = CGRect(x: 16, y: 1440 + 10, width: 1888, height: 40)

    let strip = ReservedStrip.from(barFrame: bar, screenFrame: screen)

    // Gap below = 10 (bar.minY 1450 − screen.minY 1440); bar top = 1490; +10 → 1500.
    #expect(strip.minWindowBottom == 1500)
}

@Test("a bar flush to the screen bottom yields a zero gap, never a negative one")
func reservedStripClampsFlushBar() {
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
    let bar = CGRect(x: 0, y: 0, width: 1280, height: 30)

    let strip = ReservedStrip.from(barFrame: bar, screenFrame: screen)

    // No gap below → the reserved top is exactly the bar's top edge.
    #expect(strip.minWindowBottom == 30)
}
#endif
