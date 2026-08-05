#if canImport(AppKit)
import Foundation
import Testing
@testable import CerebralMacAdapters

/// The publisher's real CPU window (NIC-158) — the numbers below are the behaviour the panel's
/// 60/85 thresholds were chosen against, so they are asserted at the real time constant rather
/// than a convenient one.
private let cpuTau: TimeInterval = 30
private let cadence: TimeInterval = 2

private let start = Date(timeIntervalSince1970: 1_780_000_000)

/// Feed `sample` for `seconds` at the 2 s publisher cadence, returning the final smoothed value.
private func drive(
    _ average: inout ExponentialMovingAverage, sample: Double, seconds: TimeInterval, from: Date
) -> (value: Double, end: Date) {
    var now = from
    var value = average.current ?? sample
    var elapsed: TimeInterval = 0
    while elapsed < seconds {
        now = now.addingTimeInterval(cadence)
        elapsed += cadence
        value = average.update(sample, at: now)
    }
    return (value, now)
}

@Test("the first sample is adopted verbatim — no ramp up from zero")
func seedsFromFirstSample() {
    var average = ExponentialMovingAverage(timeConstant: cpuTau)
    #expect(average.current == nil)

    // A launch at 47% must render 47%, not a fabricated climb from 0 that the machine never
    // reported (NIC-158 honesty rule).
    #expect(average.update(47, at: start) == 47)
    #expect(average.current == 47)
}

@Test("a single spike cannot reach the warning threshold")
func singleSpikeIsRejected() {
    var average = ExponentialMovingAverage(timeConstant: cpuTau)
    average.update(10, at: start)

    // One 2 s tick at 100% from a 10% idle baseline.
    let spiked = average.update(100, at: start.addingTimeInterval(cadence))

    // alpha = 1 - e^(-2/30) ≈ 0.0645 → 10 + 0.0645 * 90 ≈ 15.8. Nowhere near yellow (60).
    #expect(spiked > 15 && spiked < 17)
    #expect(spiked < 60, "a transient spike must never colour the bar")

    // And it decays back toward idle rather than lingering. One time constant closes ~63% of the
    // remaining gap (15.8 → ~12.1), three closes essentially all of it.
    let afterOneTau = drive(&average, sample: 10, seconds: cpuTau, from: start.addingTimeInterval(cadence))
    #expect(afterOneTau.value > 10 && afterOneTau.value < 13)
    let (afterThreeTau, _) = drive(&average, sample: 10, seconds: cpuTau * 2, from: afterOneTau.end)
    #expect(afterThreeTau < 10.5)
}

@Test("sustained load crosses the panel thresholds on the expected timescale")
func sustainedLoadClimbs() {
    var average = ExponentialMovingAverage(timeConstant: cpuTau)
    average.update(10, at: start)

    // Yellow (60) at ~24 s of sustained 100%.
    let (atTwenty, twenty) = drive(&average, sample: 100, seconds: 20, from: start)
    #expect(atTwenty < 60, "must not be yellow yet at 20s")
    let (atThirty, thirty) = drive(&average, sample: 100, seconds: 10, from: twenty)
    #expect(atThirty > 60, "must be yellow by 30s")

    // Red (85) at ~54 s.
    let (atFifty, fifty) = drive(&average, sample: 100, seconds: 20, from: thirty)
    #expect(atFifty < 85, "must not be red yet at 50s")
    let (atSixty, _) = drive(&average, sample: 100, seconds: 10, from: fifty)
    #expect(atSixty > 85, "must be red by 60s of pegging the machine")
}

@Test("repeated spiking accumulates like the equivalent steady load")
func dutyCycleAccumulates() {
    // Thermally, "100% half the time" and "a steady 50%" are the same thing, so the bar must read
    // them the same — this is the distinction the smoothing is meant to capture.
    var spiky = ExponentialMovingAverage(timeConstant: cpuTau)
    var steady = ExponentialMovingAverage(timeConstant: cpuTau)
    spiky.update(0, at: start)
    steady.update(0, at: start)

    var now = start
    for tick in 0..<120 {
        now = now.addingTimeInterval(cadence)
        spiky.update(tick.isMultiple(of: 2) ? 100 : 0, at: now)
        steady.update(50, at: now)
    }

    let spikyValue = try! #require(spiky.current)
    let steadyValue = try! #require(steady.current)
    #expect(abs(spikyValue - steadyValue) < 12, "a 50% duty cycle must land near a steady 50%")
    #expect(spikyValue > 40 && spikyValue < 65)
}

@Test("weighting is by elapsed time, not sample count")
func weightsByElapsedTime() {
    // One 30 s gap must move the average far more than one 2 s tick of the same sample — otherwise
    // a late tick (or the immediate tick after a resume) would be under-weighted.
    var slow = ExponentialMovingAverage(timeConstant: cpuTau)
    var fast = ExponentialMovingAverage(timeConstant: cpuTau)
    slow.update(0, at: start)
    fast.update(0, at: start)

    let slowValue = slow.update(100, at: start.addingTimeInterval(30))
    let fastValue = fast.update(100, at: start.addingTimeInterval(2))

    #expect(slowValue > fastValue * 5)
    // One full time constant closes ~63% of the gap.
    #expect(slowValue > 60 && slowValue < 66)
}

@Test("a reset drops the history so the next sample re-seeds — it never coasts")
func resetReseeds() {
    var average = ExponentialMovingAverage(timeConstant: cpuTau)
    _ = drive(&average, sample: 90, seconds: 120, from: start)
    #expect(try! #require(average.current) > 80)

    average.reset()
    #expect(average.current == nil)

    // The next reading is adopted whole rather than blended with a curve that no longer describes
    // the machine — the recovered-channel and resumed-publisher path.
    #expect(average.update(5, at: start.addingTimeInterval(600)) == 5)
}

@Test("a non-advancing or backwards timestamp contributes nothing")
func rejectsNonMonotonicTimestamps() {
    var average = ExponentialMovingAverage(timeConstant: cpuTau)
    average.update(20, at: start)

    // A duplicate timestamp must not divide by zero or double-count.
    #expect(average.update(100, at: start) == 20)
    // A backwards clock must not produce a negative alpha, which would amplify the difference
    // away from the sample instead of damping toward it.
    #expect(average.update(100, at: start.addingTimeInterval(-60)) == 20)
}
#endif
