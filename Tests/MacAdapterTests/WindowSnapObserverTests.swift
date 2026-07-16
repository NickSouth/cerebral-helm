#if canImport(AppKit)
import CoreGraphics
import Foundation
import Testing

import CerebralMacAdapters

/// Window-snap correction (NIC-144 inc 2): the pure geometry decision, plus the
/// observer's settle / echo-suppression / trust control flow over a fake surface.

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let strip = ReservedStrip(screenFrame: screen, minWindowBottom: 60)

// MARK: - Correction geometry

@Test("a maximized window is shrunk so its bottom rests on the reserved line, top fixed")
func maximizedWindowIsShrunk() {
    let maximized = CGRect(x: 0, y: 0, width: 1000, height: 800) // bottom 0, top 800
    let corrected = WindowSnapCorrection.correct(frame: maximized, strips: [strip])
    #expect(corrected == CGRect(x: 0, y: 60, width: 1000, height: 740))
}

@Test("a window already clear of the reserved line is left untouched")
func clearWindowIsUntouched() {
    let clear = CGRect(x: 100, y: 60, width: 400, height: 300) // bottom exactly on the line
    #expect(WindowSnapCorrection.correct(frame: clear, strips: [strip]) == nil)
    let higher = CGRect(x: 100, y: 200, width: 400, height: 300)
    #expect(WindowSnapCorrection.correct(frame: higher, strips: [strip]) == nil)
}

@Test("a small window wholly inside the reserved zone is lifted, preserving its size")
func windowInsideZoneIsTranslated() {
    let inside = CGRect(x: 300, y: 10, width: 200, height: 40) // top 50, still below the line 60
    let corrected = WindowSnapCorrection.correct(frame: inside, strips: [strip])
    // Same size, bottom pinned to the line.
    #expect(corrected == CGRect(x: 300, y: 60, width: 200, height: 40))
}

@Test("with no reserved strips reported, nothing is corrected")
func noStripsMeansNoCorrection() {
    let maximized = CGRect(x: 0, y: 0, width: 1000, height: 800)
    #expect(WindowSnapCorrection.correct(frame: maximized, strips: []) == nil)
}

@Test("a window on another display is matched to the strip it most overlaps")
func multiDisplayPicksTheOverlappingStrip() {
    let second = ReservedStrip(
        screenFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800), minWindowBottom: 40
    )
    // Wholly on the second display, dropped onto its bar.
    let onSecond = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    #expect(
        WindowSnapCorrection.correct(frame: onSecond, strips: [strip, second])
            == CGRect(x: 1000, y: 40, width: 1000, height: 760)
    )
}

// MARK: - Observer control flow

private final class FakeSnapSurface: WindowSnapSurface {
    var isProcessTrusted = true
    var settable = true
    private(set) var setCalls: [(pid: pid_t, frame: CGRect)] = []
    private var handler: ((pid_t, CGRect) -> Void)?

    // Model the live surface: no Accessibility trust means no observation is wired, so
    // nothing is ever delivered until trust is granted and observation (re)starts.
    func startObserving(onWindowChanged: @escaping (pid_t, CGRect) -> Void) {
        guard isProcessTrusted else { return }
        handler = onWindowChanged
    }
    func stopObserving() { handler = nil }
    func setFrame(pid: pid_t, appKitFrame: CGRect) -> Bool {
        setCalls.append((pid, appKitFrame))
        return settable
    }

    /// Drive an observed move/resize as if Accessibility reported it.
    func emit(pid: pid_t, frame: CGRect) { handler?(pid, frame) }
}

/// Synchronous settle so the control flow is deterministic without a run loop.
private func makeObserver(_ surface: FakeSnapSurface) -> WindowSnapObserver {
    let observer = WindowSnapObserver(
        surface: surface, reservedStrips: { [strip] }, settleInterval: 0
    )
    observer.start()
    return observer
}

@Test("an intruding window is corrected exactly once")
func intrudingWindowIsCorrected() {
    let surface = FakeSnapSurface()
    let observer = makeObserver(surface)
    surface.emit(pid: 42, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(surface.setCalls.count == 1)
    #expect(surface.setCalls.first?.frame == CGRect(x: 0, y: 60, width: 1000, height: 740))
    _ = observer
}

@Test("a non-intruding window is never touched")
func nonIntrudingWindowIsIgnored() {
    let surface = FakeSnapSurface()
    let observer = makeObserver(surface)
    surface.emit(pid: 42, frame: CGRect(x: 100, y: 200, width: 400, height: 300))
    #expect(surface.setCalls.isEmpty)
    _ = observer
}

@Test("the observer's own correction echoing back does not loop")
func ownCorrectionDoesNotLoop() {
    let surface = FakeSnapSurface()
    let observer = makeObserver(surface)
    surface.emit(pid: 42, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    // Accessibility reports the window at the frame we just set — must not re-correct.
    surface.emit(pid: 42, frame: CGRect(x: 0, y: 60, width: 1000, height: 740))
    #expect(surface.setCalls.count == 1)
    _ = observer
}

@Test("an app that refuses the move is left alone after one honest attempt")
func unresizableWindowIsLeftAlone() {
    let surface = FakeSnapSurface()
    surface.settable = false
    let observer = makeObserver(surface)
    surface.emit(pid: 42, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    // One attempt that returns false; a further identical report re-attempts (we never
    // recorded a success to suppress), but there is no runaway loop within a settle.
    #expect(surface.setCalls.count == 1)
    _ = observer
}

@Test("without Accessibility trust the observer is an inert no-op")
func noTrustIsNoOp() {
    let surface = FakeSnapSurface()
    surface.isProcessTrusted = false
    let observer = makeObserver(surface)
    surface.emit(pid: 42, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(surface.setCalls.isEmpty)
    _ = observer
}

@Test("the observer re-arms and corrects once Accessibility is granted mid-session")
func reArmsAfterTrustGranted() {
    let surface = FakeSnapSurface()
    surface.isProcessTrusted = false
    let observer = WindowSnapObserver(surface: surface, reservedStrips: { [strip] }, settleInterval: 0)
    observer.start()
    // Not trusted yet — no observation, so nothing is corrected.
    surface.emit(pid: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(surface.setCalls.isEmpty)

    // Trust granted; the app reactivating re-arms observation without a relaunch.
    surface.isProcessTrusted = true
    observer.start()
    surface.emit(pid: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(surface.setCalls.count == 1)
}
#endif
