import Foundation

/// How far through the sprint the work is, against how far through the sprint the clock is
/// (NIC-228).
///
/// **Computed here so the model never has to.** The composer is handed a word and two percentages
/// rather than forty issues and a date range, because arithmetic over a list is exactly where a
/// model invents a number — and the standing rule from the measurements is that context substitutes
/// for reasoning. The system prompt tells it that derived figures are already computed and that it
/// must never calculate its own; this is what makes that promise keepable.
public struct SprintPace: Equatable, Sendable {
    /// Whether the work is keeping up with the clock.
    public enum Status: String, Equatable, Sendable {
        case behind
        case onPace = "on-pace"
        case ahead
    }

    /// What the percentages are measured in.
    ///
    /// Points when the sprint is estimated, issue counts when it is not. A team that has not
    /// estimated anything still has a pace, and reporting 0% complete because every estimate is
    /// absent would be a confident lie about a sprint that is going fine.
    public enum Basis: String, Equatable, Sendable {
        case points
        case issues
    }

    public let basis: Basis
    /// Excludes cancelled work. A cancelled ticket is neither done nor outstanding, and counting it
    /// in the denominator makes a finished sprint look incomplete forever.
    public let total: Int
    public let done: Int
    public let inProgress: Int
    public let percentComplete: Int
    public let percentElapsed: Int
    public let daysElapsed: Int
    public let daysRemaining: Int
    public let status: Status

    /// How far `percentComplete` may trail `percentElapsed` before the sprint counts as behind.
    ///
    /// A judgement, not a measurement, and stated as a constant so it is visible as one. Ten points
    /// is wide enough that a sprint is not called behind for being one day out of step, and narrow
    /// enough that the word still means something by mid-cycle. Symmetric, so "ahead" is held to the
    /// same standard.
    public static let tolerance = 10

    /// The pace of `sprint` at `now`, or nil when there is nothing to measure — no running cycle,
    /// a cycle with no duration, or a cycle holding no countable work.
    ///
    /// Nil rather than a zeroed value: "between cycles" and "0% done" are different facts, and a
    /// snapshot carrying the second when the first is true would have the brief report a sprint
    /// that has not started as one going badly.
    public static func measure(_ sprint: Sprint, now: Date, calendar: Calendar = .current) -> SprintPace? {
        guard let cycle = sprint.cycle else { return nil }

        let duration = cycle.endsAt.timeIntervalSince(cycle.startsAt)
        guard duration > 0 else { return nil }

        // Cancelled work leaves the denominator entirely — see `total`.
        let counted = sprint.issues.filter { $0.state != .canceled }
        guard !counted.isEmpty else { return nil }

        let estimated = counted.compactMap(\.estimate).reduce(0, +)
        // Points when anything is estimated at all, issue counts when nothing is. Mixed estimation
        // uses points and treats an unestimated issue as zero, which understates it — the honest
        // alternative would be to invent a number for it, and inventing is the thing being avoided.
        let basis: Basis = estimated > 0 ? .points : .issues

        func weight(_ issue: SprintIssue) -> Int {
            basis == .points ? (issue.estimate ?? 0) : 1
        }

        let total = counted.reduce(0) { $0 + weight($1) }
        let done = counted.filter { $0.state == .completed }.reduce(0) { $0 + weight($1) }
        let inProgress = counted.filter { $0.state == .started }.reduce(0) { $0 + weight($1) }
        guard total > 0 else { return nil }

        let percentComplete = percentage(done, of: total)
        // Clamped at both ends: a cycle read before it starts or after it ends is a real occurrence
        // — Linear keeps the last cycle current for a moment — and a negative or 120% figure would
        // reach the model as a fact about the sprint rather than as an artefact of when it looked.
        let elapsed = now.timeIntervalSince(cycle.startsAt) / duration
        let percentElapsed = max(0, min(100, Int((elapsed * 100).rounded())))

        return SprintPace(
            basis: basis,
            total: total,
            done: done,
            inProgress: inProgress,
            percentComplete: percentComplete,
            percentElapsed: percentElapsed,
            daysElapsed: wholeDays(from: cycle.startsAt, to: min(max(now, cycle.startsAt), cycle.endsAt), calendar: calendar),
            daysRemaining: wholeDays(from: min(max(now, cycle.startsAt), cycle.endsAt), to: cycle.endsAt, calendar: calendar),
            status: status(complete: percentComplete, elapsed: percentElapsed)
        )
    }

    static func status(complete: Int, elapsed: Int) -> Status {
        if complete < elapsed - tolerance { return .behind }
        if complete > elapsed + tolerance { return .ahead }
        return .onPace
    }

    private static func percentage(_ part: Int, of whole: Int) -> Int {
        guard whole > 0 else { return 0 }
        return Int(((Double(part) / Double(whole)) * 100).rounded())
    }

    /// Whole days between two instants, never negative.
    ///
    /// Counted in the given calendar rather than by dividing seconds, so a daylight-saving boundary
    /// inside a cycle does not silently add or drop a day — a two-week cycle crossing one is
    /// otherwise 13.96 days, which truncates to 13.
    private static func wholeDays(from: Date, to: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }
}
