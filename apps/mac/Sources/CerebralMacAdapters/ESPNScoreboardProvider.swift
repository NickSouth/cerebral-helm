// ESPN scoreboard reads (quick-actions phase 4) — the `check-scoreboard` action's provider.
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Reads current NFL games and PGA tournaments from ESPN's public site API.
///
/// **Undocumented on purpose, with eyes open** (docs/quick-actions/PLAN.md): nothing free covers
/// both a team sport and an individual leaderboard, and the endpoints answer `200` with no key.
/// The cost is that a field can move without an announcement — so every mapper here is
/// *defensive by construction*: a malformed event is dropped and the rest of the payload still
/// renders, and a league that fails entirely never takes the other one down with it. A scoreboard
/// missing one game is far better than a surface that refuses to open.
///
/// **Golf is 1.2 MB per fetch and cannot be made smaller** — `/leaderboard` 404s and `?limit=` is
/// ignored (both probed). That is why this is fetched on demand rather than polled, and why the
/// trimming happens here: what crosses the bridge is a few fields per competitor, not the wire
/// payload.
///
/// The full field is kept rather than truncated: the report expands from a top ten to everyone,
/// and re-fetching a megabyte to reveal rows the host already had would be absurd.
public struct ESPNScoreboardProvider: SportsScoreboardProvider {
    /// The leagues this action covers, in the order the picker lists them.
    static let leagues: [(id: String, path: String)] = [
        ("nfl", "/apis/site/v2/sports/football/nfl/scoreboard"),
        ("pga", "/apis/site/v2/sports/golf/pga/scoreboard")
    ]

    private let session: URLSession
    private let host: String

    public init(
        session: URLSession? = nil,
        host: String = "https://site.api.espn.com",
        resourceTimeout: TimeInterval = 20
    ) {
        self.host = host
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
    }

    public func events() async throws -> [SportsEvent] {
        var collected: [SportsEvent] = []
        var failures: [String] = []

        for league in Self.leagues {
            do {
                collected.append(contentsOf: try await fetch(league: league.id, path: league.path))
            } catch {
                // One league failing must not hide the other: an NFL Sunday should still render
                // when golf's endpoint is having a moment.
                failures.append(league.id)
            }
        }
        guard !collected.isEmpty || failures.isEmpty else {
            throw SportsScoreboardError.providerFailed(
                "Couldn't reach \(failures.joined(separator: " or ")) right now."
            )
        }
        return collected
    }

    private func fetch(league: String, path: String) async throws -> [SportsEvent] {
        guard let url = URL(string: host + path) else {
            throw SportsScoreboardError.providerFailed("Bad \(league) endpoint.")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw SportsScoreboardError.providerFailed("Cancelled.")
        } catch {
            throw SportsScoreboardError.providerFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SportsScoreboardError.providerFailed("\(league) returned HTTP \(http.statusCode).")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SportsScoreboardError.providerFailed("\(league) returned an unreadable response.")
        }
        return Self.decodeEvents(root, league: league)
    }

    // MARK: - Pure mapping (unit-tested)

    /// Maps one league's payload. Anything unrecognizable is dropped rather than throwing — the
    /// whole defensive posture of reading an undocumented source.
    static func decodeEvents(_ root: [String: Any], league: String) -> [SportsEvent] {
        let events = root["events"] as? [[String: Any]] ?? []
        return events.compactMap { decodeEvent($0, league: league) }
    }

    static func decodeEvent(_ node: [String: Any], league: String) -> SportsEvent? {
        guard let id = node["id"] as? String, let name = node["name"] as? String else { return nil }
        let competition = (node["competitions"] as? [[String: Any]])?.first
        // The status hangs off the event for NFL and off the competition for golf, so both are
        // tried rather than assuming one shape holds for every league.
        let status = (node["status"] as? [String: Any]) ?? (competition?["status"] as? [String: Any])
        let type = status?["type"] as? [String: Any]

        let competitorNodes = competition?["competitors"] as? [[String: Any]] ?? []
        return SportsEvent(
            id: id,
            league: league,
            name: name,
            shortName: (node["shortName"] as? String) ?? name,
            state: SportsEventState(rawValue: (type?["state"] as? String) ?? "") ?? .scheduled,
            detail: (type?["shortDetail"] as? String)
                ?? (type?["description"] as? String)
                ?? "",
            venue: venueName(competition),
            competitors: competitorNodes.compactMap(decodeCompetitor),
            leaderboard: decodeLeaderboard(competitorNodes)
        )
    }

    /// The venue, with its city when the source gives one. Nil for golf, which carries no course
    /// in this payload — so "what course is this?" genuinely needs another source, and the report
    /// says nothing rather than inventing one.
    static func venueName(_ competition: [String: Any]?) -> String? {
        guard let venue = competition?["venue"] as? [String: Any],
              let name = venue["fullName"] as? String, !name.isEmpty
        else { return nil }
        let address = venue["address"] as? [String: Any]
        let city = address?["city"] as? String
        return city.map { "\(name) · \($0)" } ?? name
    }

    /// A team competitor. Requires the abbreviation, which is what a scoreboard row is keyed on —
    /// a nameless side is not a side. Golf competitors have no team and drop out here.
    static func decodeCompetitor(_ node: [String: Any]) -> SportsCompetitor? {
        guard let team = node["team"] as? [String: Any],
              let abbreviation = team["abbreviation"] as? String
        else { return nil }
        return SportsCompetitor(
            abbreviation: abbreviation,
            name: (team["displayName"] as? String) ?? abbreviation,
            score: string(node["score"]) ?? "0",
            color: (team["color"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isHome: (node["homeAway"] as? String) == "home",
            record: ((node["records"] as? [[String: Any]])?.first?["summary"] as? String)
        )
    }

    /// The ranked field. Rows without an athlete are not leaderboard rows — that is how a team
    /// game's competitors are excluded without branching on the league.
    static func decodeLeaderboard(_ nodes: [[String: Any]]) -> [SportsLeaderboardEntry] {
        nodes.enumerated().compactMap { index, node in
            guard let athlete = node["athlete"] as? [String: Any],
                  let name = athlete["displayName"] as? String
            else { return nil }
            let status = node["status"] as? [String: Any]
            return SportsLeaderboardEntry(
                order: (node["order"] as? Int) ?? index + 1,
                position: (status?["position"] as? [String: Any])?["displayName"] as? String,
                name: name,
                score: string(node["score"]) ?? "E",
                thru: string(status?["thru"])
            )
        }
        .sorted { $0.order < $1.order }
    }

    /// Reads a value the source sends as either a string or a number — `score` arrives both ways
    /// across the two leagues, and a type assumption here would silently blank a column.
    static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? Int { return String(number) }
        if let number = value as? Double {
            return number == number.rounded() ? String(Int(number)) : String(number)
        }
        return nil
    }
}
#endif
