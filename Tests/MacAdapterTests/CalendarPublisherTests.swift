// NIC-126 Increment 5: streaming the Today panel as schedule.changed events per relevance profile,
// resolving each event to a mode with the layered resolver + the user's calendar→mode map.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters

/// The four-mode catalog, matching config/calendar/profiles.json. Distinct profiles (sorted):
/// academic, all, engineering, leisure — so a tick emits four schedule.changed events.
private func calendarTestCatalog() -> CalendarProfileCatalog {
    CalendarProfileCatalog(
        defaultMode: "executive",
        modeProfiles: [
            "executive": "all", "developer": "engineering", "school": "academic", "entertainment": "leisure",
        ],
        tagAliases: ["dev": "developer"]
    )
}

private func calendarEvent(id: String, title: String, calendarId: String, notes: String? = nil, hour: Int) -> CalendarEvent {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: hour))!
    return CalendarEvent(id: id, title: title, start: start, calendarId: calendarId, calendarTitle: calendarId, notes: notes)
}

/// One decoded schedule.changed event, so a test can assert per-profile content precisely.
private struct ScheduleEnvelope: Decodable {
    struct Payload: Decodable {
        struct Schedule: Decodable {
            struct Item: Decodable { let id: String; let title: String }
            let state: String
            let items: [Item]
            let emptyMessage: String?
        }
        let profile: String
        let schedule: Schedule
    }
    let type: String
    let payload: Payload
}

private final class ScheduleEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
    /// The first decoded event for each profile (a later re-emit of the same profile is ignored).
    func byProfile() -> [String: ScheduleEnvelope.Payload.Schedule] {
        var map: [String: ScheduleEnvelope.Payload.Schedule] = [:]
        for json in all {
            guard let env = try? JSONDecoder().decode(ScheduleEnvelope.self, from: Data(json.utf8)) else { continue }
            if map[env.payload.profile] == nil { map[env.payload.profile] = env.payload.schedule }
        }
        return map
    }
}

private func waitForSchedule(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test("emits one schedule.changed per profile; the catch-all shows all events, filtered profiles their slice")
func calendarPublisherEmitsPerProfile() async throws {
    let collector = ScheduleEventCollector()
    let publisher = CalendarPublisher(
        catalog: calendarTestCatalog(),
        calendarModeMap: { [:] },
        provider: MockCalendarProvider(events: [
            calendarEvent(id: "a", title: "Team standup", calendarId: "cal-work", hour: 9), // → executive / all
            calendarEvent(id: "b", title: "Sprint sync", calendarId: "cal-x", notes: "#dev", hour: 11), // → developer / engineering
        ]),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSchedule(3000) { collector.byProfile().count >= 4 }
    await publisher.stop()

    let first = try #require(try? CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8)))
    #expect(first.type == .scheduleChanged)

    let byProfile = collector.byProfile()
    // "all" (Executive) shows every event.
    #expect(byProfile["all"]?.state == "ready")
    #expect(byProfile["all"]?.items.map(\.id) == ["a", "b"])
    // "engineering" (Developer) shows only the #dev-tagged event.
    #expect(byProfile["engineering"]?.state == "ready")
    #expect(byProfile["engineering"]?.items.map(\.id) == ["b"])
    // "academic" and "leisure" have nothing → honest empty.
    #expect(byProfile["academic"]?.state == "empty")
    #expect(byProfile["leisure"]?.state == "empty")
}

@Test("the user's calendar→mode map routes an untagged event to the mapped mode's profile")
func calendarPublisherAppliesMapping() async throws {
    let collector = ScheduleEventCollector()
    let publisher = CalendarPublisher(
        catalog: calendarTestCatalog(),
        calendarModeMap: { ["cal-school": "school"] },
        provider: MockCalendarProvider(events: [
            calendarEvent(id: "c", title: "Lecture", calendarId: "cal-school", hour: 10), // mapped → school / academic
        ]),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSchedule(3000) { collector.byProfile().count >= 4 }
    await publisher.stop()

    let byProfile = collector.byProfile()
    #expect(byProfile["academic"]?.state == "ready")
    #expect(byProfile["academic"]?.items.map(\.id) == ["c"])
    // Executive still sees it (the catch-all shows everything), but Developer/Entertainment do not.
    #expect(byProfile["all"]?.items.map(\.id) == ["c"])
    #expect(byProfile["engineering"]?.state == "empty")
    #expect(byProfile["leisure"]?.state == "empty")
}

@Test("a denied Calendar grant emits an honest grant-access unavailable for every profile")
func calendarPublisherPermissionDenied() async throws {
    let collector = ScheduleEventCollector()
    let publisher = CalendarPublisher(
        catalog: calendarTestCatalog(),
        calendarModeMap: { [:] },
        provider: MockCalendarProvider(error: .permissionDenied),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSchedule(3000) { collector.byProfile().count >= 4 }
    await publisher.stop()

    for (_, schedule) in collector.byProfile() {
        #expect(schedule.state == "unavailable")
        #expect(schedule.emptyMessage?.contains("Grant Calendar access") == true)
    }
}

@Test("a provider failure emits a generic unavailable, never leaking the diagnostic")
func calendarPublisherProviderFailure() async throws {
    let collector = ScheduleEventCollector()
    let publisher = CalendarPublisher(
        catalog: calendarTestCatalog(),
        calendarModeMap: { [:] },
        provider: MockCalendarProvider(error: .providerFailed("store token=abc123 down")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSchedule(3000) { collector.byProfile().count >= 4 }
    await publisher.stop()

    let all = collector.all.joined(separator: "\n")
    #expect(all.contains("\"state\":\"unavailable\""))
    #expect(!all.contains("Grant Calendar access")) // not the permission message
    #expect(!all.contains("abc123")) // raw diagnostic never leaked
}

@Test("a paused calendar publisher emits nothing; resuming emits immediately")
func calendarPublisherPauseResume() async throws {
    let collector = ScheduleEventCollector()
    let publisher = CalendarPublisher(
        catalog: calendarTestCatalog(),
        calendarModeMap: { [:] },
        provider: MockCalendarProvider(events: [
            calendarEvent(id: "a", title: "Standup", calendarId: "cal-work", hour: 9),
        ]),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSchedule(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitForSchedule(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
