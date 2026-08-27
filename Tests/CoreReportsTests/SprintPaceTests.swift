import Foundation
import Testing
@testable import CerebralCore

/// NIC-228: the sprint's pace, computed so the model never has to.
///
/// This is the arithmetic a composer would otherwise be asked to do over forty issues and a date
/// range — which is exactly where a model invents a figure. The system prompt promises that derived
/// numbers are already computed and forbids it calculating its own; these tests are what make that
/// promise keepable, so the cases that matter are the ones where a careless calculation would give a
/// confidently wrong answer: cancelled work, unestimated work, and a clock read outside the cycle.

private let zone = TimeZone(identifier: "America/New_York")!

private let reference: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}()

/// Midnight by default, so a cycle's elapsed fraction lands on whole days and every expectation
/// below is legible arithmetic rather than a number only the implementation could produce.
private func at(_ day: Int, _ hour: Int = 0) -> Date {
    reference.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
}

/// A one-week cycle: Monday 24 August to Monday 31 August.
private func cycle() -> SprintCycle {
    SprintCycle(number: 3, name: nil, startsAt: at(24, 0), endsAt: at(31, 0))
}

private func issue(
    _ identifier: String,
    state: SprintIssueState,
    estimate: Int? = nil,
    priority: Int = 3
) -> SprintIssue {
    SprintIssue(
        identifier: identifier, title: "Issue \(identifier)", stateName: state.rawValue,
        state: state, priority: priority, estimate: estimate, labels: []
    )
}

private func sprint(_ issues: [SprintIssue], cycle: SprintCycle? = cycle()) -> Sprint {
    Sprint(projectName: "CerebralHelm", cycle: cycle, issues: issues, truncated: false)
}

private func measure(_ issues: [SprintIssue], on day: Int, cycle: SprintCycle? = cycle()) -> SprintPace? {
    SprintPace.measure(sprint(issues, cycle: cycle), now: at(day), calendar: reference)
}

// MARK: - Points

@Test("points are the basis when the sprint is estimated")
func pointsAreTheBasis() throws {
    // 12 of 34 points done, three days into a seven-day cycle: 35% complete against 43% elapsed.
    let pace = try #require(measure([
        issue("A", state: .completed, estimate: 8),
        issue("B", state: .completed, estimate: 4),
        issue("C", state: .started, estimate: 5),
        issue("D", state: .unstarted, estimate: 13),
        issue("E", state: .backlog, estimate: 4)
    ], on: 27))

    #expect(pace.basis == .points)
    #expect(pace.total == 34)
    #expect(pace.done == 12)
    #expect(pace.inProgress == 5)
    #expect(pace.percentComplete == 35)
    #expect(pace.percentElapsed == 43)
    // Within the ten-point tolerance, so the sprint is keeping up rather than slipping.
    #expect(pace.status == .onPace)
    #expect(pace.daysElapsed == 3)
    #expect(pace.daysRemaining == 4)
}

@Test("cancelled work leaves the denominator entirely")
func cancelledWorkIsNotCounted() throws {
    // Counting a cancelled ticket as outstanding makes a finished sprint look incomplete forever —
    // the work did not move, it stopped existing.
    let pace = try #require(measure([
        issue("A", state: .completed, estimate: 5),
        issue("B", state: .canceled, estimate: 8)
    ], on: 27))

    #expect(pace.total == 5)
    #expect(pace.percentComplete == 100)
}

@Test("an unestimated sprint is measured in issues rather than reported as nothing")
func unestimatedSprintFallsBackToCounts() throws {
    // Every estimate absent would sum to zero points, and 0/0 reported as "0% complete" is a
    // confident lie about a sprint that is going fine.
    let pace = try #require(measure([
        issue("A", state: .completed),
        issue("B", state: .completed),
        issue("C", state: .started),
        issue("D", state: .unstarted)
    ], on: 27))

    #expect(pace.basis == .issues)
    #expect(pace.total == 4)
    #expect(pace.done == 2)
    #expect(pace.percentComplete == 50)
}

@Test("a partly estimated sprint uses points and does not invent the missing ones")
func partialEstimatesUsePoints() throws {
    let pace = try #require(measure([
        issue("A", state: .completed, estimate: 5),
        issue("B", state: .unstarted)
    ], on: 27))

    // The unestimated issue weighs nothing, which understates the sprint. The honest alternative
    // would be to invent a number for it, and inventing is the thing being avoided.
    #expect(pace.basis == .points)
    #expect(pace.total == 5)
    #expect(pace.percentComplete == 100)
}

// MARK: - Status

@Test("status is a band, not a comparison")
func statusUsesATolerance() {
    // Exactly level, and one point either side of it, all read as on pace: a sprint should not be
    // called behind for being a few hours out of step with the clock.
    #expect(SprintPace.status(complete: 43, elapsed: 43) == .onPace)
    #expect(SprintPace.status(complete: 34, elapsed: 43) == .onPace)
    #expect(SprintPace.status(complete: 52, elapsed: 43) == .onPace)

    // Past the band in either direction the word starts meaning something.
    #expect(SprintPace.status(complete: 32, elapsed: 43) == .behind)
    #expect(SprintPace.status(complete: 54, elapsed: 43) == .ahead)

    // Symmetric: "ahead" is held to the same standard as "behind".
    #expect(SprintPace.tolerance == 10)
}

@Test("a sprint that has done nothing halfway through is behind")
func behindIsDetected() throws {
    let pace = try #require(measure([
        issue("A", state: .unstarted, estimate: 8),
        issue("B", state: .started, estimate: 5)
    ], on: 28))

    #expect(pace.status == .behind)
    #expect(pace.percentComplete == 0)
    // In-progress work is reported separately rather than counted as half done: a composer choosing
    // what to suggest needs to know something is already underway.
    #expect(pace.inProgress == 5)
}

// MARK: - Nothing to measure

@Test("between cycles there is no pace at all, rather than a zeroed one")
func noCycleMeansNoPace() {
    // "Between cycles" and "0% done" are different facts. A zeroed pace would have the brief report
    // a sprint that has not started as one going badly.
    #expect(measure([issue("A", state: .unstarted, estimate: 3)], on: 27, cycle: nil) == nil)
}

@Test("an empty cycle, an all-cancelled cycle and a zero-length cycle measure nothing")
func degenerateCyclesMeasureNothing() {
    #expect(measure([], on: 27) == nil)
    #expect(measure([issue("A", state: .canceled, estimate: 5)], on: 27) == nil)
    // A cycle with no duration would divide by zero on elapsed time.
    let instant = SprintCycle(number: 1, name: nil, startsAt: at(24, 0), endsAt: at(24, 0))
    #expect(measure([issue("A", state: .unstarted, estimate: 3)], on: 24, cycle: instant) == nil)
}

// MARK: - Reading outside the window

@Test("a clock outside the cycle is clamped rather than reported as a fact about the sprint")
func elapsedIsClamped() throws {
    let work = [issue("A", state: .completed, estimate: 5), issue("B", state: .unstarted, estimate: 5)]

    // Linear keeps the last cycle current for a moment after it ends, so both of these happen.
    let before = try #require(measure(work, on: 20))
    #expect(before.percentElapsed == 0)
    #expect(before.daysElapsed == 0)

    let after = try #require(measure(work, on: 40))
    #expect(after.percentElapsed == 100)
    #expect(after.daysRemaining == 0)
    // Without clamping these would reach the model as −57% and 120% — artefacts of when it looked,
    // arriving as facts about the sprint.
}
