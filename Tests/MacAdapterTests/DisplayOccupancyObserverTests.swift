#if canImport(AppKit)
import XCTest
import CoreGraphics
@testable import CerebralMacAdapters

/// NIC-152. Two things are worth holding here, and neither can be checked by looking at a desktop:
/// the **rule** (what counts as a display being occupied — a product decision with several
/// deliberate exceptions) and the **hysteresis** (which only misbehaves on timing no one reproduces
/// by hand).
final class DisplayOccupancyObserverTests: XCTestCase {
    private let laptop = OccupancyDisplay(id: "laptop", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    private let external = OccupancyDisplay(id: "external", frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440))
    private let ownPID: pid_t = 501

    private func window(
        _ id: UInt32,
        pid: pid_t,
        _ frame: CGRect
    ) -> OccupancyWindow {
        OccupancyWindow(windowID: id, pid: pid, frame: frame)
    }

    private func occupied(
        _ windows: [OccupancyWindow],
        counting own: Set<UInt32> = []
    ) -> Set<String> {
        DisplayOccupancyObserver.occupiedDisplays(
            windows: windows,
            displays: [laptop, external],
            ownPID: ownPID,
            countedOwnWindows: own
        )
    }

    // MARK: - The rule

    func testEmptyDesktopOccupiesNothing() {
        XCTAssertEqual(occupied([]), [])
    }

    func testAnotherApplicationsWindowOccupiesOnlyItsOwnDisplay() {
        // The requirement in one case: the display with the user's work on it recedes, and the one
        // showing nothing but CerebralHelm does not. A single global focus flag cannot say this.
        let editor = window(1, pid: 900, CGRect(x: 1600, y: 200, width: 1200, height: 800))
        XCTAssertEqual(occupied([editor]), ["external"])
    }

    func testAWindowSpanningBothDisplaysOccupiesBoth() {
        let wide = window(1, pid: 900, CGRect(x: 700, y: 100, width: 2000, height: 700))
        XCTAssertEqual(occupied([wide]), ["laptop", "external"])
    }

    func testASliverAcrossTheBoundaryDoesNotOccupyTheDisplayItBarelyTouches() {
        // Overhangs the laptop by 4pt. Any-intersection would recede a whole screen because a
        // window on the *other* monitor is a few pixels wide at its edge.
        let nudged = window(1, pid: 900, CGRect(x: 1436, y: 300, width: 1000, height: 600))
        XCTAssertEqual(occupied([nudged]), ["external"])
    }

    func testCerebralHelmsOwnWindowsAreExcludedByDefault() {
        // The sidebar is the case that proves the rule: a real native window on this display, so a
        // naive "any window" test would dim the whole surface on every accidental edge brush.
        let sidebar = window(10, pid: ownPID, CGRect(x: 0, y: 0, width: 360, height: 900))
        let navigator = window(11, pid: ownPID, CGRect(x: 1000, y: 200, width: 264, height: 640))
        XCTAssertEqual(occupied([sidebar, navigator]), [])
    }

    func testSettingsCountsWhenTheHostNamesIt() {
        // Settings is a place you go to work; the busy dashboard behind it is noise.
        let settings = window(20, pid: ownPID, CGRect(x: 200, y: 100, width: 880, height: 560))
        XCTAssertEqual(occupied([settings]), [])
        XCTAssertEqual(occupied([settings], counting: [20]), ["laptop"])
    }

    func testAnUnnamedOwnWindowStillDoesNotCountWhileSettingsIsOpen() {
        // The confirmation panel is normal-level and would otherwise qualify, but it is a momentary
        // interruption *about* the dashboard — dimming behind it would just flash.
        let confirmation = window(21, pid: ownPID, CGRect(x: 1600, y: 400, width: 520, height: 300))
        XCTAssertEqual(occupied([confirmation], counting: [20]), [])
    }

    func testADisplayWithNoAreaIsIgnoredRatherThanDividingByZero() {
        let collapsed = OccupancyDisplay(id: "ghost", frame: .zero)
        let anywhere = window(1, pid: 900, CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(
            DisplayOccupancyObserver.occupiedDisplays(
                windows: [anywhere], displays: [collapsed], ownPID: ownPID, countedOwnWindows: []
            ),
            []
        )
    }

    // MARK: - Hysteresis

    /// Drives the observer on a clock the test controls, so the debounce can be exercised without
    /// waiting in real time.
    private final class Desktop: OnScreenWindowReading, @unchecked Sendable {
        var windows: [OccupancyWindow] = []
        func onScreenWindows() -> [OccupancyWindow] { windows }
    }

    private func makeObserver(
        _ desktop: Desktop,
        clock: @escaping () -> Date
    ) -> (DisplayOccupancyObserver, () -> [(String, Bool)]) {
        var reported: [(String, Bool)] = []
        let observer = DisplayOccupancyObserver(
            source: desktop,
            ownPID: ownPID,
            displays: { [self.laptop] },
            countedOwnWindows: { [] },
            now: clock
        )
        observer.onOccupancyChange = { id, receded in reported.append((id, receded)) }
        return (observer, { reported })
    }

    func testFirstReadingIsAdoptedImmediately() {
        let desktop = Desktop()
        desktop.windows = [window(1, pid: 900, laptop.frame)]
        var time = Date(timeIntervalSince1970: 0)
        let (observer, reported) = makeObserver(desktop) { time }

        observer.refresh()
        // No debounce on the first sighting: a display that is already covered when CerebralHelm
        // launches must not spend the delay looking fully present first.
        XCTAssertEqual(reported().count, 1)
        XCTAssertEqual(reported().first?.1, true)
        _ = time
    }

    func testRecedingWaitsForTheDisplayToStayCovered() {
        let desktop = Desktop()
        var time = Date(timeIntervalSince1970: 0)
        let (observer, reported) = makeObserver(desktop) { time }

        observer.refresh()
        XCTAssertEqual(reported().map(\.1), [false])

        desktop.windows = [window(1, pid: 900, laptop.frame)]
        observer.refresh()
        XCTAssertEqual(reported().count, 1, "the change is only a candidate at this point")

        time = time.addingTimeInterval(DisplayOccupancyObserver.recedeDelay - 0.01)
        observer.refresh()
        XCTAssertEqual(reported().count, 1, "still short of the delay")

        time = time.addingTimeInterval(0.02)
        observer.refresh()
        XCTAssertEqual(reported().map(\.1), [false, true])
    }

    func testAWindowThatOpensAndClosesQuicklyNeverRecedesAnything() {
        let desktop = Desktop()
        var time = Date(timeIntervalSince1970: 0)
        let (observer, reported) = makeObserver(desktop) { time }
        observer.refresh()

        desktop.windows = [window(1, pid: 900, laptop.frame)]
        observer.refresh()
        time = time.addingTimeInterval(0.4)
        desktop.windows = []
        observer.refresh()

        time = time.addingTimeInterval(10)
        observer.refresh()
        // The whole reason the debounce exists: without it this strobes the dashboard through a
        // 620ms fade and back.
        XCTAssertEqual(reported().map(\.1), [false])
    }

    func testReturningIsQuickerThanReceding() {
        let desktop = Desktop()
        desktop.windows = [window(1, pid: 900, laptop.frame)]
        var time = Date(timeIntervalSince1970: 0)
        let (observer, reported) = makeObserver(desktop) { time }
        observer.refresh()
        XCTAssertEqual(reported().map(\.1), [true])

        desktop.windows = []
        observer.refresh()
        time = time.addingTimeInterval(DisplayOccupancyObserver.returnDelay + 0.01)
        observer.refresh()
        // Being slow about "the user came back" is far more annoying than being slow about "the
        // user left", so the two delays are deliberately different.
        XCTAssertEqual(reported().map(\.1), [true, false])
        XCTAssertLessThan(
            DisplayOccupancyObserver.returnDelay,
            DisplayOccupancyObserver.recedeDelay
        )
    }

    func testASteadyDesktopIsSilent() {
        let desktop = Desktop()
        desktop.windows = [window(1, pid: 900, laptop.frame)]
        var time = Date(timeIntervalSince1970: 0)
        let (observer, reported) = makeObserver(desktop) { time }
        observer.refresh()

        for _ in 0..<20 {
            time = time.addingTimeInterval(DisplayOccupancyObserver.pollInterval)
            observer.refresh()
        }
        XCTAssertEqual(reported().count, 1, "polling must not re-report a state that never changed")
    }

    func testCurrentStateAnswersForASurfaceThatMissedTheTransition() {
        let desktop = Desktop()
        desktop.windows = [window(1, pid: 900, laptop.frame)]
        let observer = DisplayOccupancyObserver(
            source: desktop,
            ownPID: ownPID,
            displays: { [self.laptop] },
            countedOwnWindows: { [] }
        )
        observer.refresh()
        // A companion backdrop built for a hot-plugged display, or a webview whose handshake only
        // just completed, has heard nothing — the observer speaks on change alone.
        XCTAssertTrue(observer.currentState(of: "laptop"))
        XCTAssertFalse(observer.currentState(of: "never-seen"))
    }

    // MARK: - Coordinate conversion

    func testCoreGraphicsRectsAreFlippedIntoAppKitSpace() {
        // CoreGraphics measures y down from the top of the primary display; AppKit measures it up
        // from the bottom of that same display. Getting this backwards would put every window on
        // the wrong half of the desktop — and still look plausible on a single centred monitor.
        let primaryTop: CGFloat = 900
        let topLeft = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(
            LiveOnScreenWindows.appKitFrame(topLeft, primaryTop: primaryTop),
            CGRect(x: 0, y: 600, width: 400, height: 300)
        )

        let bottomEdge = CGRect(x: 100, y: 600, width: 400, height: 300)
        XCTAssertEqual(
            LiveOnScreenWindows.appKitFrame(bottomEdge, primaryTop: primaryTop),
            CGRect(x: 100, y: 0, width: 400, height: 300)
        )
    }
}
#endif
