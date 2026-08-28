import Foundation

/// The work in the current sprint, as far as a brief needs to describe it (NIC-228).
///
/// A "sprint" here **is** Linear's cycle — the product word for the same thing, and the word the
/// snapshot uses. Cycles mirror Linear's rather than being invented locally, so the length and the
/// boundaries are read, never assumed.
///
/// Deliberately narrower than `LinearProjectCycle`, which the projects widget renders. A brief has
/// no use for issue URLs, state colours, sort order or avatar initials, and every field that does
/// not reach the model is a field it cannot misread or quote back.
public struct Sprint: Equatable, Sendable {
    /// The project's name **as Linear spells it**, which may differ in casing from the descriptor's
    /// `linear_project`. Echoing the canonical form back is what confirms which project matched.
    public let projectName: String
    /// The running cycle, or nil when there is none. Between cycles is a real state and reads
    /// differently from "a cycle is running and nothing is in it".
    public let cycle: SprintCycle?
    public let issues: [SprintIssue]
    /// True when Linear had more issues than one page returned. Surfaced rather than swallowed: a
    /// list silently cut at the page size reads as complete when it is not, and a pace computed
    /// from a truncated list is confidently wrong.
    public let truncated: Bool

    public init(projectName: String, cycle: SprintCycle?, issues: [SprintIssue], truncated: Bool) {
        self.projectName = projectName
        self.cycle = cycle
        self.issues = issues
        self.truncated = truncated
    }
}

public struct SprintCycle: Equatable, Sendable {
    public let number: Int
    /// Cycles are usually unnamed.
    public let name: String?
    public let startsAt: Date
    public let endsAt: Date

    public init(number: Int, name: String?, startsAt: Date, endsAt: Date) {
        self.number = number
        self.name = name
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

/// Where an issue sits in the workflow.
///
/// Grouped on Linear's state **type**, never its name: the type is one of a fixed set, and unlike a
/// name it survives the user renaming a status. "Next-Up" and "Todo" are both `unstarted`, and a
/// pace computed from names would break the first time a column was renamed.
public enum SprintIssueState: String, Equatable, Sendable {
    case backlog
    case unstarted
    case started
    case completed
    case canceled

    /// Maps Linear's own `type` string, defaulting to `backlog` for a value this does not know —
    /// the choice that keeps an unrecognised state out of both the done and the in-flight counts
    /// rather than inflating either.
    public init(linearType: String) {
        self = SprintIssueState(rawValue: linearType) ?? .backlog
    }
}

public struct SprintIssue: Equatable, Sendable {
    public let identifier: String
    public let title: String
    /// The status as Linear displays it ("Next-Up"), for a brief that names a ticket's column.
    public let stateName: String
    public let state: SprintIssueState
    /// Linear's scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low. Lower is more urgent, which is
    /// worth stating because every other scale in this app runs the other way.
    public let priority: Int
    /// Fibonacci points, or nil when the issue carries no estimate.
    public let estimate: Int?
    public let labels: [String]

    public init(
        identifier: String,
        title: String,
        stateName: String,
        state: SprintIssueState,
        priority: Int,
        estimate: Int?,
        labels: [String]
    ) {
        self.identifier = identifier
        self.title = title
        self.stateName = stateName
        self.state = state
        self.priority = priority
        self.estimate = estimate
        self.labels = labels
    }
}

/// Why the sprint could not be read. Each degrades into a different sentence, because each asks
/// something different of the reader.
public enum SprintError: Error, Equatable, Sendable {
    /// No project declares a `linear_project`, so there is nothing to look up. A normal state, not
    /// a fault: an unlinked machine simply has no sprint to report.
    case noLinkedProject
    /// A project declares a `linear_project` that Linear has no project for — almost always a typo.
    /// Distinguished because a misspelled name returns zero issues, which is byte-identical to a
    /// correctly-linked project with an empty cycle. Reporting a typo as "nothing to do" is the
    /// worst kind of wrong, because it looks like an answer.
    case projectNotFound(String)
    /// No API key stored yet.
    case credentialsMissing
    case unavailable(String)
}

/// Port that reads the current sprint for whichever project the brief reports on (NIC-228).
///
/// Takes no arguments on purpose. *Which* project is a deterministic rule over local descriptors
/// (``SprintProjectResolver``) and *where the issues come from* is an API call; composing the two is
/// the concrete's job at the app edge, exactly as `EventKitCalendarProvider` composes a store and a
/// window behind ``CalendarProvider``.
public protocol SprintProvider: Sendable {
    func currentSprint() async throws -> Sprint
}

/// A fixed-outcome ``SprintProvider`` for tests and for any build with no Linear key: it yields the
/// sprint (or throws the error) it was constructed with.
public struct MockSprintProvider: SprintProvider {
    private let outcome: Result<Sprint, SprintError>

    public init(sprint: Sprint) { self.outcome = .success(sprint) }
    public init(error: SprintError) { self.outcome = .failure(error) }

    public func currentSprint() async throws -> Sprint { try outcome.get() }
}
