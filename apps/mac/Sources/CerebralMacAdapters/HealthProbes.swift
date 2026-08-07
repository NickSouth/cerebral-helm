// Live third-party probes for the health checks (quick actions phase 5).
#if canImport(AppKit)
import Foundation

/// The probes that verify a **third-party contract**, not just reachability.
///
/// Each one asks the cheapest question that would actually notice the failure it exists to catch,
/// and each returns `nil` for "still good" or a sentence for "here is what moved". Every parser is
/// separated from its request so the interesting half is unit-testable against a recorded body —
/// which matters more here than usual, because the whole point is that these payloads change.
///
/// None of them writes. None of them costs a metered request where a free one exists.

// MARK: - Linear

enum LinearProbe {
    /// Verified live 2026-08-03: `https://api.linear.app/graphql`, `Authorization: <key>` with
    /// **no** `Bearer` prefix, and GraphQL answers `200` with an `errors` array — so the status
    /// code is not the signal and the body has to be read.
    static func run(token: String, session: URLSession) async -> String? {
        guard let url = URL(string: "https://api.linear.app/graphql") else {
            return "Couldn't build the Linear endpoint."
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        // `viewer` is the smallest authenticated query there is: it proves the key works and reads
        // nothing about anyone's issues.
        request.httpBody = Data(#"{"query":"{ viewer { id } }"}"#.utf8)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                return "The API key was rejected."
            }
            return parse(data)
        } catch {
            return error.localizedDescription
        }
    }

    /// GraphQL's 200-with-errors is the trap: a caller that trusted the status code would call an
    /// expired key healthy.
    static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Linear returned an unreadable response."
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let message = errors.first?["message"] as? String
            return message.map { "Linear refused: \($0)" } ?? "Linear returned an error."
        }
        guard
            let payload = root["data"] as? [String: Any],
            let viewer = payload["viewer"] as? [String: Any],
            viewer["id"] is String
        else {
            return "Linear answered, but not in the shape we read."
        }
        return nil
    }
}

// MARK: - GitHub

enum GitHubProbe {
    /// `/rate_limit` is the one GitHub endpoint that **does not itself count against the limit**,
    /// so this verifies the token and reports the remaining budget without spending any of it.
    static func run(token: String, session: URLSession) async -> String? {
        guard let url = URL(string: "https://api.github.com/rate_limit") else {
            return "Couldn't build the GitHub endpoint."
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                return "The token was rejected — it may have expired."
            }
            return parse(data)
        } catch {
            return error.localizedDescription
        }
    }

    /// A token that is valid but **exhausted** is a real failure with a different fix from an
    /// invalid one, so it is reported as itself rather than as "GitHub is down".
    static func parse(_ data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rate = (root["resources"] as? [String: Any])?["core"] as? [String: Any],
            let remaining = rate["remaining"] as? Int
        else {
            return "GitHub answered, but not in the shape we read."
        }
        return remaining == 0 ? "Rate limit exhausted — it resets within the hour." : nil
    }
}

// MARK: - ESPN

enum ESPNProbe {
    /// The one endpoint in the app that is explicitly undocumented, read on the stated
    /// understanding that it can change without notice. This asserts the exact fields
    /// `ESPNScoreboardProvider` maps, so a shape change surfaces here rather than as an empty
    /// scoreboard nobody can explain.
    ///
    /// **Out of season it legitimately returns zero events**, which is not a failure — so the
    /// check verifies the *envelope* always, and the event shape only when there is an event.
    static func validate(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "ESPN returned an unreadable response."
        }
        guard let events = root["events"] as? [[String: Any]] else {
            return "ESPN's payload no longer has an `events` array."
        }
        guard let first = events.first else {
            return nil // No games today. Nothing has moved.
        }
        guard first["id"] is String, first["name"] is String else {
            return "An ESPN event no longer carries `id` and `name`."
        }
        guard let competition = (first["competitions"] as? [[String: Any]])?.first else {
            return "An ESPN event no longer carries `competitions`."
        }
        guard let competitors = competition["competitors"] as? [[String: Any]], !competitors.isEmpty else {
            return "An ESPN competition no longer carries `competitors`."
        }
        // The status hangs off the EVENT for NFL and off the COMPETITION for golf — both are
        // tried, exactly as the mapper does, so this cannot pass on a shape the mapper would fail.
        let status = (first["status"] as? [String: Any]) ?? (competition["status"] as? [String: Any])
        guard (status?["type"] as? [String: Any])?["state"] is String else {
            return "An ESPN event no longer reports `status.type.state`."
        }
        guard let team = competitors.first?["team"] as? [String: Any],
              team["abbreviation"] is String
        else {
            return "An ESPN competitor no longer carries `team.abbreviation`."
        }
        return nil
    }
}

// MARK: - Open-Meteo

enum OpenMeteoProbe {
    /// Documented and stable, but free and unauthenticated — so it is checked because it costs
    /// nothing to check, and because "the weather stopped" is otherwise indistinguishable from
    /// "location is denied".
    static func validate(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Open-Meteo returned an unreadable response."
        }
        guard let current = root["current"] as? [String: Any] else {
            return "Open-Meteo's payload no longer has a `current` block."
        }
        guard current["temperature_2m"] is Double || current["temperature_2m"] is Int else {
            return "Open-Meteo no longer reports `current.temperature_2m`."
        }
        return nil
    }
}
#endif
