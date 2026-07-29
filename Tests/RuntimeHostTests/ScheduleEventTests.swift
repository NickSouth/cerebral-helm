import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-126 Increment 2: mapping a calendar-provider result into a `DashboardScheduleRegion`, and
/// emitting it as a `schedule.changed` bridge event keyed by relevance profile. A fixed UTC calendar
/// keeps the today/tonight kind and the local-clock start string deterministic.

private var scheduleUTCCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func scheduleDate(_ hour: Int, _ minute: Int = 0) -> Date {
    scheduleUTCCalendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27, hour: hour, minute: minute)
    )!
}

private func scheduleEvent(
    id: String, title: String, hour: Int, minute: Int = 0, isAllDay: Bool = false, location: String? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: id, title: title, start: scheduleDate(hour, minute), isAllDay: isAllDay,
        calendarId: "cal", calendarTitle: "Cal", location: location
    )
}

@Test("events map to a ready region, sorted by start, with local-clock times")
func scheduleReadyMapping() {
    let region = BridgeEventFactory.schedule(
        from: .success([
            scheduleEvent(id: "2", title: "Afternoon review", hour: 14, minute: 30),
            scheduleEvent(id: "1", title: "Morning standup", hour: 9, location: "Room 4B"),
        ]),
        calendar: scheduleUTCCalendar
    )
    #expect(region.state == .ready)
    // Sorted by start ascending — the 9am event comes first though it was passed second.
    #expect(region.items.map(\.id) == ["1", "2"])
    #expect(region.items.first?.title == "Morning standup")
    // The event's location flows through for the row's hover tooltip; absent → nil.
    #expect(region.items.first?.location == "Room 4B")
    #expect(region.items.last?.location == nil)
    // The panel slices HH:mm out of the start string, so it must read local wall-clock time.
    #expect(region.items.first?.start == "2026-07-27T09:00:00")
    #expect(region.items.last?.start == "2026-07-27T14:30:00")
    #expect(region.emptyMessage == nil)
}

@Test("kind is tonight at/after 18:00, today before; an all-day event is today with no time")
func scheduleKindMapping() {
    let region = BridgeEventFactory.schedule(
        from: .success([
            scheduleEvent(id: "morning", title: "Class", hour: 9),
            scheduleEvent(id: "evening", title: "Concert", hour: 20),
            scheduleEvent(id: "allday", title: "Conference", hour: 0, isAllDay: true),
        ]),
        calendar: scheduleUTCCalendar
    )
    let byId = Dictionary(uniqueKeysWithValues: region.items.map { ($0.id, $0) })
    #expect(byId["morning"]?.kind == .today)
    #expect(byId["evening"]?.kind == .tonight)
    #expect(byId["allday"]?.kind == .today)
    // An all-day event carries no time (start omitted, never a misleading 00:00).
    #expect(byId["allday"]?.start == nil)
}

@Test("a ready region is capped at the earliest four events (the panel reserves four rows)")
func scheduleCapsAtFour() {
    let region = BridgeEventFactory.schedule(
        from: .success((9...16).map { scheduleEvent(id: "\($0)", title: "Slot \($0)", hour: $0) }),
        calendar: scheduleUTCCalendar
    )
    #expect(region.state == .ready)
    #expect(region.items.count == 4)
    // The four earliest, in order.
    #expect(region.items.map(\.id) == ["9", "10", "11", "12"])
}

@Test("an empty result maps to an empty region, nothing fabricated")
func scheduleEmptyMapping() {
    let region = BridgeEventFactory.schedule(from: .success([]), calendar: scheduleUTCCalendar)
    #expect(region.state == .empty)
    #expect(region.items.isEmpty)
    #expect(region.emptyMessage == "Nothing scheduled.")
}

@Test("a denied permission maps to an honest unavailable that guides to Settings")
func schedulePermissionDeniedMapping() {
    let region = BridgeEventFactory.schedule(
        from: .failure(CalendarError.permissionDenied), calendar: scheduleUTCCalendar
    )
    #expect(region.state == .unavailable)
    #expect(region.items.isEmpty)
    #expect(region.emptyMessage == "Grant Calendar access in Settings → Setup to see your schedule.")
}

@Test("a generic provider failure maps to a generic unavailable, never leaking the diagnostic")
func scheduleProviderFailureMapping() {
    let region = BridgeEventFactory.schedule(
        from: .failure(CalendarError.providerFailed("token=abc123 store unavailable")),
        calendar: scheduleUTCCalendar
    )
    #expect(region.state == .unavailable)
    #expect(region.emptyMessage == "Your schedule isn't available right now.")
    #expect(region.emptyMessage?.contains("abc123") == false)
}

@Test("the region emits as a schedule.changed event carrying its profile; round-trips the contract")
func scheduleEmitsChangedEvent() throws {
    let region = BridgeEventFactory.schedule(
        from: .success([scheduleEvent(id: "1", title: "Morning standup", hour: 9)]),
        calendar: scheduleUTCCalendar
    )
    let event = BridgeEventFactory.scheduleChangedEvent(
        region: region, profile: "all", id: "brevt_test00000126", timestamp: scheduleDate(9)
    )

    #expect(event.type == .scheduleChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"schedule.changed\""))
    #expect(json.contains("\"profile\":\"all\""))
    #expect(json.contains("\"title\":\"Morning standup\""))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .scheduleChanged)
    #expect(decoded.eventID == "brevt_test00000126")
}
