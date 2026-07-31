import Foundation
import Testing

import CerebralCore

/// NIC-126 Increment 2: the deterministic layered relevance resolver — an event's `#[mode]` tag
/// wins, else its calendar→mode mapping, else the default mode; and per-profile filtering where the
/// catch-all profile shows everything and any other profile shows only its own events.

private let resolverCatalog = CalendarProfileCatalog(
    defaultMode: "executive",
    modeProfiles: [
        "executive": "all",
        "developer": "engineering",
        "school": "academic",
        "entertainment": "leisure",
    ],
    tagAliases: ["dev": "developer", "work": "executive", "study": "school"]
)

private func resolverEvent(
    id: String = "e", calendarId: String = "cal-unmapped", notes: String? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: "Event \(id)",
        start: Date(timeIntervalSince1970: 1_700_000_000),
        calendarId: calendarId,
        calendarTitle: calendarId,
        notes: notes
    )
}

@Test("a #[mode] tag in the notes wins over both the calendar mapping and the default")
func resolverTagWins() {
    // Calendar maps to executive, but the #dev tag overrides it.
    let resolver = CalendarRelevanceResolver(
        catalog: resolverCatalog, calendarModeMap: ["cal-work": "executive"]
    )
    let event = resolverEvent(calendarId: "cal-work", notes: "Sprint sync #dev please")
    #expect(resolver.mode(for: event) == "developer")
    #expect(resolver.profile(for: event) == "engineering")
}

@Test("the calendar→mode mapping wins when there is no tag")
func resolverMapWins() {
    let resolver = CalendarRelevanceResolver(
        catalog: resolverCatalog, calendarModeMap: ["cal-school": "school"]
    )
    let event = resolverEvent(calendarId: "cal-school")
    #expect(resolver.mode(for: event) == "school")
    #expect(resolver.profile(for: event) == "academic")
}

@Test("an event with neither a tag nor a mapping falls back to the default mode")
func resolverDefaults() {
    let resolver = CalendarRelevanceResolver(catalog: resolverCatalog)
    let event = resolverEvent(calendarId: "cal-unmapped")
    #expect(resolver.mode(for: event) == "executive")
    #expect(resolver.profile(for: event) == "all")
}

@Test("a raw mode id used directly as a tag resolves (e.g. #school)")
func resolverRawModeTag() {
    let resolver = CalendarRelevanceResolver(catalog: resolverCatalog)
    #expect(resolver.mode(for: resolverEvent(notes: "Exam #school")) == "school")
    // A lone '#' and an unknown tag are ignored, falling through to the default.
    #expect(resolver.mode(for: resolverEvent(notes: "just a # and #nope")) == "executive")
}

@Test("the catch-all profile shows every event; any other profile shows only its own")
func resolverFiltersByProfile() {
    let resolver = CalendarRelevanceResolver(
        catalog: resolverCatalog, calendarModeMap: ["cal-school": "school"]
    )
    let events = [
        resolverEvent(id: "a", calendarId: "cal-unmapped"),          // → executive / all
        resolverEvent(id: "b", calendarId: "cal-work", notes: "#dev"), // → developer / engineering
        resolverEvent(id: "c", calendarId: "cal-school"),             // → school / academic
        resolverEvent(id: "d", calendarId: "cal-unmapped", notes: "#dev"), // → developer / engineering
    ]

    // "all" is the default mode's profile → the catch-all, showing everything in order.
    #expect(resolver.events(forProfile: "all", from: events).map(\.id) == ["a", "b", "c", "d"])
    // "engineering" → only the developer-resolved events.
    #expect(resolver.events(forProfile: "engineering", from: events).map(\.id) == ["b", "d"])
    // "academic" → only the school-resolved event.
    #expect(resolver.events(forProfile: "academic", from: events).map(\.id) == ["c"])
    // "leisure" → none of these.
    #expect(resolver.events(forProfile: "leisure", from: events).isEmpty)
}
