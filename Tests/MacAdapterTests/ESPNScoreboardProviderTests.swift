// Quick actions phase 4: reading ESPN's public site API for `check-scoreboard`.
//
// The endpoint shapes here were captured from live probes on 2026-08-03 — the NFL preseason
// scoreboard and a finished PGA event. The source is undocumented, so every one of these tests is
// really the same assertion: a shape change must degrade, never throw.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore

@Test("an NFL event maps to two competitors with their scores and colours")
func espnDecodesNFLEvent() throws {
    let node: [String: Any] = [
        "id": "401873271",
        "name": "Carolina Panthers at Arizona Cardinals",
        "shortName": "CAR VS ARI",
        "status": ["type": ["state": "pre", "shortDetail": "8/6 - 8:00 PM EDT"]],
        "competitions": [[
            "competitors": [
                [
                    "homeAway": "home", "score": "0",
                    "team": ["abbreviation": "ARI", "displayName": "Arizona Cardinals", "color": "a40227"],
                    "records": [["summary": "0-0"]]
                ],
                [
                    "homeAway": "away", "score": "0",
                    "team": ["abbreviation": "CAR", "displayName": "Carolina Panthers", "color": "0085ca"]
                ]
            ]
        ]]
    ]
    let event = try #require(ESPNScoreboardProvider.decodeEvent(node, league: "nfl"))
    #expect(event.state == .scheduled)
    #expect(event.detail == "8/6 - 8:00 PM EDT")
    #expect(event.competitors.count == 2)
    let home = try #require(event.competitors.first { $0.isHome })
    #expect(home.abbreviation == "ARI")
    // The colour arrives in the same payload, which is what lets a scoreboard look like one
    // without fetching a logo.
    #expect(home.color == "a40227")
    #expect(home.record == "0-0")
    // A team game has no leaderboard — the two collections are never both populated.
    #expect(event.leaderboard.isEmpty)
}

@Test("the venue is carried for NFL and absent for golf")
func espnCarriesVenue() throws {
    // NFL supplies a stadium; the golf scoreboard carries no course at all — which is exactly why
    // "what course is this?" needs another source, and why the report says nothing rather than
    // inventing one.
    let withVenue: [String: Any] = [
        "venue": [
            "fullName": "Tom Benson Hall of Fame Stadium",
            "address": ["city": "Canton", "state": "OH"]
        ]
    ]
    #expect(ESPNScoreboardProvider.venueName(withVenue) == "Tom Benson Hall of Fame Stadium · Canton")
    // No city is still a venue, not a dangling separator.
    #expect(ESPNScoreboardProvider.venueName(["venue": ["fullName": "Somewhere"]]) == "Somewhere")
    #expect(ESPNScoreboardProvider.venueName(nil) == nil)
    #expect(ESPNScoreboardProvider.venueName(["venue": ["fullName": ""]]) == nil)
}

@Test("a golf event maps to a ranked field and no competitors")
func espnDecodesGolfEvent() throws {
    let node: [String: Any] = [
        "id": "401811960",
        "name": "Rocket Classic",
        "competitions": [[
            "status": ["type": ["state": "post", "description": "Final"]],
            "competitors": [
                ["order": 2, "score": -16, "athlete": ["displayName": "Xander Schauffele"]],
                ["order": 1, "score": -18, "athlete": ["displayName": "Michael Thorbjornsen"]]
            ]
        ]]
    ]
    let event = try #require(ESPNScoreboardProvider.decodeEvent(node, league: "pga"))
    // The status hangs off the COMPETITION for golf and off the event for NFL; both are tried.
    #expect(event.state == .finished)
    #expect(event.detail == "Final")
    #expect(event.competitors.isEmpty)
    // Sorted by the provider's order, not by payload order.
    #expect(event.leaderboard.map(\.name) == ["Michael Thorbjornsen", "Xander Schauffele"])
    // `score` arrives as a NUMBER here and a STRING for NFL; both read.
    #expect(event.leaderboard.first?.score == "-18")
    // A finished event reports no position or thru — normal, not a fault.
    #expect(event.leaderboard.first?.position == nil)
    #expect(event.leaderboard.first?.thru == nil)
}

@Test("a malformed event is dropped and the rest of the payload still renders")
func espnDropsMalformedEvents() {
    // The whole defensive posture of reading an undocumented source: one changed field must not
    // take down the scoreboard.
    let root: [String: Any] = [
        "events": [
            ["name": "No id"],
            ["id": "2"],
            ["id": "3", "name": "Fine", "competitions": [["competitors": []]]]
        ]
    ]
    let events = ESPNScoreboardProvider.decodeEvents(root, league: "nfl")
    #expect(events.map(\.id) == ["3"])
    // A missing status is a scheduled event with no detail, not a crash.
    #expect(events.first?.state == .scheduled)
    #expect(events.first?.detail == "")
}

@Test("a payload with no events at all is empty, not an error")
func espnHandlesEmptyPayload() {
    #expect(ESPNScoreboardProvider.decodeEvents([:], league: "nfl").isEmpty)
    #expect(ESPNScoreboardProvider.decodeEvents(["events": []], league: "pga").isEmpty)
}

@Test("scores read whether the source sends a string or a number")
func espnReadsMixedScoreTypes() {
    // Observed live: NFL sends "0", golf sends -18. A type assumption blanks a column silently.
    #expect(ESPNScoreboardProvider.string("21") == "21")
    #expect(ESPNScoreboardProvider.string(-18) == "-18")
    #expect(ESPNScoreboardProvider.string(3.0) == "3")
    #expect(ESPNScoreboardProvider.string("") == nil)
    #expect(ESPNScoreboardProvider.string(nil) == nil)
}

@Test("both leagues are read, in the order the picker lists them")
func espnCoversBothLeagues() {
    #expect(ESPNScoreboardProvider.leagues.map(\.id) == ["nfl", "pga"])
    #expect(ESPNScoreboardProvider.leagues.allSatisfy { $0.path.hasSuffix("/scoreboard") })
}
#endif
