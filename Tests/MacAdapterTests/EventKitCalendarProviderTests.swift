// NIC-126 Increment 3: the EventKit adapter's pure EKEvent→CalendarEvent mapping, tested through the
// `EventKitReading` seam without a live `EKEventStore` (the live fetch + TCC grant are a manual smoke).
// The colour conversion is exercised with a real CGColor. `map`/`colorHex`/`EventKitReading` are
// `internal`, hence `@testable`. Gated so Linux CI compiles this target empty.
#if canImport(EventKit)
import Foundation
import Testing
import AppKit

@testable import CerebralMacAdapters
import CerebralCore

private func calendarReading(
    id: String? = "evt-1",
    title: String? = "Standup",
    start: Date? = Date(timeIntervalSince1970: 1_700_000_000),
    end: Date? = nil,
    isAllDay: Bool = false,
    notes: String? = nil,
    location: String? = nil,
    calendarId: String? = "cal-work",
    calendarTitle: String? = "Work",
    colorHex: String? = nil
) -> EventKitReading {
    EventKitReading(
        eventIdentifier: id, title: title, startDate: start, endDate: end, isAllDay: isAllDay,
        notes: notes, location: location, calendarIdentifier: calendarId, calendarTitle: calendarTitle,
        colorHex: colorHex
    )
}

@Test("a full timed event maps to a CalendarEvent, carrying calendar identity, notes, and location")
func eventKitMapsFullEvent() throws {
    let event = try #require(EventKitCalendarProvider.map(calendarReading(
        end: Date(timeIntervalSince1970: 1_700_003_600), notes: "#dev sync",
        location: "Room 4B", colorHex: "#3366cc"
    )))
    #expect(event.id == "evt-1")
    #expect(event.title == "Standup")
    #expect(event.isAllDay == false)
    #expect(event.calendarId == "cal-work")
    #expect(event.calendarTitle == "Work")
    #expect(event.notes == "#dev sync")
    #expect(event.location == "Room 4B")
    #expect(event.colorHex == "#3366cc")
}

@Test("a blank location maps to nil, never an empty string")
func eventKitBlankLocationIsNil() throws {
    #expect(try #require(EventKitCalendarProvider.map(calendarReading(location: ""))).location == nil)
    #expect(try #require(EventKitCalendarProvider.map(calendarReading(location: nil))).location == nil)
}

@Test("an all-day event preserves its all-day flag")
func eventKitMapsAllDay() throws {
    let event = try #require(EventKitCalendarProvider.map(calendarReading(isAllDay: true)))
    #expect(event.isAllDay == true)
}

@Test("a degenerate event (no id, no start, or a blank title) is skipped, never shown")
func eventKitSkipsDegenerate() {
    #expect(EventKitCalendarProvider.map(calendarReading(id: nil)) == nil)
    #expect(EventKitCalendarProvider.map(calendarReading(title: nil)) == nil)
    #expect(EventKitCalendarProvider.map(calendarReading(title: "   ")) == nil)
    #expect(EventKitCalendarProvider.map(calendarReading(start: nil)) == nil)
}

@Test("a missing calendar id/title falls back to empty, never fabricated")
func eventKitFallsBackOnMissingCalendar() throws {
    let event = try #require(EventKitCalendarProvider.map(
        calendarReading(calendarId: nil, calendarTitle: nil)
    ))
    #expect(event.calendarId == "")
    #expect(event.calendarTitle == "")
    #expect(event.colorHex == nil)
}

@Test("colorHex converts a CGColor to #rrggbb in sRGB, and nil to nil")
func eventKitColorHex() throws {
    let blue = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor
    #expect(EventKitCalendarProvider.colorHex(from: blue) == "#3366cc")
    #expect(EventKitCalendarProvider.colorHex(from: nil) == nil)
}
#endif
