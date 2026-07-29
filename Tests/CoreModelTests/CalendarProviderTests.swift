import Foundation
import Testing

import CerebralCore

/// NIC-126 Increment 2: the portable calendar-provider contract — a provider-neutral
/// ``CalendarEvent`` + window-driven ``CalendarProvider`` port with a fixed-outcome mock. The real
/// macOS EventKit read lands in the Mac adapter (Increment 3).

private func calendarFixedInterval() -> DateInterval {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return DateInterval(start: start, duration: 86_400)
}

@Test("the mock provider yields its constructed events, ignoring the window")
func calendarMockYieldsEvents() async throws {
    let provider = MockCalendarProvider(events: [
        CalendarEvent(id: "1", title: "Standup", start: Date(timeIntervalSince1970: 1_700_000_100),
                      calendarId: "cal-work", calendarTitle: "Work"),
        CalendarEvent(id: "2", title: "Lunch", start: Date(timeIntervalSince1970: 1_700_000_200),
                      isAllDay: false, calendarId: "cal-personal", calendarTitle: "Personal", notes: "#fun"),
    ])

    let events = try await provider.events(within: calendarFixedInterval())
    #expect(events.count == 2)
    #expect(events.first?.title == "Standup")
    #expect(events.first?.calendarId == "cal-work")
    // Optional fields are preserved as given, never fabricated.
    #expect(events.first?.notes == nil)
    #expect(events.last?.notes == "#fun")
}

@Test("the mock provider throws its constructed error")
func calendarMockThrowsError() async {
    let provider = MockCalendarProvider(error: .permissionDenied)
    await #expect(throws: CalendarError.permissionDenied) {
        try await provider.events(within: calendarFixedInterval())
    }
}

@Test("CalendarError distinguishes a denied permission from a provider failure")
func calendarErrorCasesAreDistinct() {
    #expect(CalendarError.permissionDenied != CalendarError.providerFailed("boom"))
    #expect(CalendarError.providerFailed("a") == CalendarError.providerFailed("a"))
}
