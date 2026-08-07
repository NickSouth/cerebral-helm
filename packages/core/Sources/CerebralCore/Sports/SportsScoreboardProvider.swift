import Foundation

/// Live sports events for the `check-scoreboard` action (quick-actions phase 4/5).
///
/// A **read**, not a tool: the user is picking games and reading scores, not acting on the world.
/// It never touches the command bus, exactly like the calendar and Linear option reads — routing
/// this through the executor would put a command in the log every time a form opened.
///
/// One model covers both sports because they differ in *which* collection is populated, not in
/// shape: an NFL game fills `competitors` (two of them), a golf tournament fills `leaderboard`.
/// A single type keeps the picker — which lists both — from needing to branch before it can even
/// show a name.

/// One side of a team game: the abbreviation, the score, and the team's own colour.
///
/// The colour comes from the provider rather than a palette here, which is what lets a scoreboard
/// look like a scoreboard without fetching a logo. It is a bare hex string (`a40227`, no `#`) —
/// exactly what the source supplies, normalized by the renderer, not invented here.
public struct SportsCompetitor: Equatable, Sendable {
    public let abbreviation: String
    public let name: String
    /// The score as the provider reported it. A string because a pre-game score is `"0"` and a
    /// provider is free to send `"—"`; parsing it into an Int would invent a number for a game
    /// that has not started.
    public let score: String
    /// Bare hex, no leading `#`. Nil when the provider omitted it.
    public let color: String?
    public let isHome: Bool
    /// Win-loss record, e.g. `"0-0"`. Nil when absent.
    public let record: String?

    public init(
        abbreviation: String, name: String, score: String, color: String?, isHome: Bool, record: String?
    ) {
        self.abbreviation = abbreviation
        self.name = name
        self.score = score
        self.color = color
        self.isHome = isHome
        self.record = record
    }
}

/// One row of an individual-event leaderboard.
public struct SportsLeaderboardEntry: Equatable, Sendable {
    /// 1-based finishing order as the provider ranked it. Ties share a displayed position, so this
    /// is the ordering key and `position` is what to show.
    public let order: Int
    /// The displayed position (`"T4"`), or nil while the field is unranked — which is what a
    /// finished event reports, so its absence is normal rather than a fault.
    public let position: String?
    public let name: String
    /// Score relative to par as reported (`"-18"`, `"E"`).
    public let score: String
    /// Holes played this round, when the round is in progress.
    public let thru: String?

    public init(order: Int, position: String?, name: String, score: String, thru: String?) {
        self.order = order
        self.position = position
        self.name = name
        self.score = score
        self.thru = thru
    }
}

/// Where an event is in its life. Mirrors the source's own three states rather than inventing a
/// richer set: "scheduled", "in progress" and "finished" is the whole distinction a scoreboard
/// needs, and anything finer would be a guess.
public enum SportsEventState: String, Equatable, Sendable {
    case scheduled = "pre"
    case inProgress = "in"
    case finished = "post"
}

public struct SportsEvent: Equatable, Sendable {
    /// The provider's event id — the value the picker returns and the report re-reads.
    public let id: String
    /// `nfl` or `pga`. A plain string so a third league needs no type change.
    public let league: String
    public let name: String
    /// The compact form (`"CAR VS ARI"`), for a picker row.
    public let shortName: String
    public let state: SportsEventState
    /// The provider's own status line — `"Final"`, `"8/6 - 8:00 PM EDT"`, `"Q3 5:42"`. Passed
    /// through rather than re-composed: the source already words this the way a viewer expects.
    public let detail: String
    /// Where it is played, when the source says. NFL supplies a stadium; the golf scoreboard
    /// carries no course at all — kept because the assemble stage should hold more than the
    /// renderer needs, so a later reader (a model answering "where is this?") is not blocked by a
    /// field that was trimmed for the current layout.
    public let venue: String?
    /// Two entries for a team game; empty for an individual event.
    public let competitors: [SportsCompetitor]
    /// The ranked field for an individual event; empty for a team game. Complete rather than
    /// truncated — the report decides how much to show, and re-fetching to expand would be a
    /// second 1 MB round trip for rows the host already had.
    public let leaderboard: [SportsLeaderboardEntry]

    public init(
        id: String,
        league: String,
        name: String,
        shortName: String,
        state: SportsEventState,
        detail: String,
        venue: String? = nil,
        competitors: [SportsCompetitor] = [],
        leaderboard: [SportsLeaderboardEntry] = []
    ) {
        self.id = id
        self.league = league
        self.name = name
        self.shortName = shortName
        self.state = state
        self.detail = detail
        self.venue = venue
        self.competitors = competitors
        self.leaderboard = leaderboard
    }
}

/// Why a scoreboard read failed, kept distinct so each degrades with its own message.
public enum SportsScoreboardError: Error, Equatable, Sendable {
    case providerFailed(String)
}

/// Port that lists the current events across the leagues the action covers.
public protocol SportsScoreboardProvider: Sendable {
    func events() async throws -> [SportsEvent]
}
