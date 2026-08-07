// Quick actions phase 5: the third-party probe parsers.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters

/// These are the checks that exist because a **third party** can change without warning, so the
/// tests are written the same way: a recorded good body must pass, and each specific field the
/// mapper depends on must, when removed, produce a message that names it.
///
/// A probe that returned "something went wrong" for every shape change would be worthless — the
/// whole value is being told *what* moved.

// MARK: - Linear

@Test("Linear's 200-with-errors is caught — the status code is not the signal")
func linearProbeReadsGraphQLErrors() {
    // Verified live 2026-08-03: GraphQL answers 200 and puts the failure in `errors`. A caller
    // that trusted the status code would call an expired key healthy.
    let body = Data(#"{"errors":[{"message":"Authentication required"}]}"#.utf8)
    let reason = LinearProbe.parse(body)
    #expect(reason?.contains("Authentication required") == true)
}

@Test("Linear passes only on the shape it actually reads")
func linearProbeAcceptsAViewer() {
    #expect(LinearProbe.parse(Data(#"{"data":{"viewer":{"id":"usr_1"}}}"#.utf8)) == nil)

    // Answered, but not with what we asked for: reported as a shape change, not as success.
    #expect(LinearProbe.parse(Data(#"{"data":{}}"#.utf8)) != nil)
    #expect(LinearProbe.parse(Data(#"{"data":{"viewer":{}}}"#.utf8)) != nil)
    #expect(LinearProbe.parse(Data("not json".utf8)) != nil)
}

// MARK: - GitHub

@Test("GitHub distinguishes an exhausted token from a broken one")
func githubProbeSeparatesExhaustionFromFailure() {
    let healthy = Data(#"{"resources":{"core":{"remaining":4998,"limit":5000}}}"#.utf8)
    #expect(GitHubProbe.parse(healthy) == nil)

    // A valid but spent token is a real problem with a different fix from an invalid one, so it
    // is reported as itself rather than as "GitHub is down".
    let spent = Data(#"{"resources":{"core":{"remaining":0,"limit":5000}}}"#.utf8)
    #expect(GitHubProbe.parse(spent)?.contains("Rate limit exhausted") == true)

    #expect(GitHubProbe.parse(Data(#"{"resources":{}}"#.utf8)) != nil)
}

// MARK: - ESPN

/// The minimum body that satisfies every field `ESPNScoreboardProvider` maps.
private func espnBody(
    events: String = """
    [{
      "id": "401",
      "name": "Team A at Team B",
      "status": {"type": {"state": "pre"}},
      "competitions": [{"competitors": [{"team": {"abbreviation": "TB"}}]}]
    }]
    """
) -> Data {
    Data("{\"events\": \(events)}".utf8)
}

@Test("ESPN passes on the shape the mapper reads")
func espnProbeAcceptsTheCurrentShape() {
    #expect(ESPNProbe.validate(espnBody()) == nil)
}

@Test("out of season, no games is not a failure")
func espnProbeAcceptsAnEmptyField() {
    // The envelope is what is verified always; the event shape only when there is an event. A
    // check that reddened every Tuesday in July would be trained out of the reader in a week.
    #expect(ESPNProbe.validate(espnBody(events: "[]")) == nil)
}

@Test("each field the mapper depends on is named when it disappears")
func espnProbeNamesWhatMoved() {
    // The envelope itself.
    #expect(ESPNProbe.validate(Data(#"{}"#.utf8))?.contains("events") == true)

    // The event's identity.
    let noName = espnBody(events: #"[{"id":"401","status":{"type":{"state":"pre"}},"competitions":[{"competitors":[{"team":{"abbreviation":"TB"}}]}]}]"#)
    #expect(ESPNProbe.validate(noName)?.contains("`id` and `name`") == true)

    // The competition wrapper.
    let noCompetition = espnBody(events: #"[{"id":"401","name":"A at B","status":{"type":{"state":"pre"}}}]"#)
    #expect(ESPNProbe.validate(noCompetition)?.contains("competitions") == true)

    // The state the report renders from.
    let noState = espnBody(events: #"[{"id":"401","name":"A at B","competitions":[{"competitors":[{"team":{"abbreviation":"TB"}}]}]}]"#)
    #expect(ESPNProbe.validate(noState)?.contains("status.type.state") == true)

    // The abbreviation a scoreboard row is keyed on.
    let noAbbreviation = espnBody(events: #"[{"id":"401","name":"A at B","status":{"type":{"state":"pre"}},"competitions":[{"competitors":[{"team":{}}]}]}]"#)
    #expect(ESPNProbe.validate(noAbbreviation)?.contains("team.abbreviation") == true)
}

@Test("golf's status lives on the competition, and that still passes")
func espnProbeAcceptsGolfsShape() {
    // The status hangs off the EVENT for NFL and off the COMPETITION for golf. The probe tries
    // both, exactly as the mapper does — otherwise it could fail a payload the app handles fine.
    let golf = espnBody(events: """
    [{
      "id": "401",
      "name": "The Open",
      "competitions": [{
        "status": {"type": {"state": "in"}},
        "competitors": [{"team": {"abbreviation": "N/A"}}]
      }]
    }]
    """)
    #expect(ESPNProbe.validate(golf) == nil)
}

// MARK: - Open-Meteo

@Test("Open-Meteo is verified down to the field the widget reads")
func openMeteoProbeChecksTheReading() {
    #expect(OpenMeteoProbe.validate(Data(#"{"current":{"temperature_2m":21.4}}"#.utf8)) == nil)
    // An integer reading is still a reading.
    #expect(OpenMeteoProbe.validate(Data(#"{"current":{"temperature_2m":21}}"#.utf8)) == nil)

    #expect(OpenMeteoProbe.validate(Data(#"{"current":{}}"#.utf8))?.contains("temperature_2m") == true)
    #expect(OpenMeteoProbe.validate(Data(#"{}"#.utf8))?.contains("current") == true)
}
#endif
