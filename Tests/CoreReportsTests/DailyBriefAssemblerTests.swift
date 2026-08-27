import Foundation
import Testing
@testable import CerebralCore

/// NIC-228: the daily brief's snapshot, gathered host-side.
///
/// The recurring theme is that **a model cannot infer what a snapshot does not say.** It is
/// instructed to use only the facts it is given, so every way a source can fail has to arrive as a
/// stated fact rather than as a missing key — otherwise "nobody could read your calendar" and "you
/// have nothing on" are the same input, and the brief will confidently report the wrong one.

// MARK: - Fixtures

private let zone = TimeZone(identifier: "America/New_York")!

private let reference: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}()

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    reference.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
}

/// 07:15 on Wednesday 26 August 2026.
private let now = at(26, 7, 15)

private func event(
    _ title: String,
    start: Date,
    end: Date? = nil,
    allDay: Bool = false,
    calendarTitle: String = "Work",
    location: String? = nil,
    notes: String? = nil
) -> CalendarEvent {
    CalendarEvent(
        id: title, title: title, start: start, end: end, isAllDay: allDay,
        calendarId: "cal", calendarTitle: calendarTitle, notes: notes, location: location
    )
}

private func message(
    _ subject: String,
    from: String = "Billing <billing@example.com>",
    preview: String? = nil,
    receivedAt: String? = "2026-08-26T09:04:00Z"
) -> MailMessage {
    MailMessage(
        id: subject, from: from, subject: subject,
        receivedAt: receivedAt, rfc822MessageID: nil, preview: preview
    )
}

/// Captures the window it was asked for. `MockCalendarProvider` ignores the interval by design, so
/// it cannot answer the question this increment actually introduces.
private actor RecordingCalendarProvider: CalendarProvider {
    private let events: [CalendarEvent]
    private(set) var requestedInterval: DateInterval?

    init(events: [CalendarEvent]) { self.events = events }

    func events(within interval: DateInterval) async throws -> [CalendarEvent] {
        requestedInterval = interval
        return events
    }

    func calendars() async throws -> [CalendarInfo] { [] }
}

private func assemble(
    calendar: (any CalendarProvider)? = MockCalendarProvider(events: []),
    mail: (any MailProvider)? = MockMailProvider(messages: [])
) async -> [String: JSONValue] {
    let snapshot = await DailyBriefAssembler(calendar: calendar, mail: mail, timeZone: zone)
        .assemble(now: now)
    return snapshot.objectValue ?? [:]
}

private func section(_ snapshot: [String: JSONValue], _ key: String) -> [String: JSONValue] {
    snapshot[key]?.objectValue ?? [:]
}

private func rows(_ section: [String: JSONValue], _ key: String) -> [[String: JSONValue]] {
    guard case let .array(items)? = section[key] else { return [] }
    return items.compactMap { $0.objectValue }
}

// MARK: - Shape

@Test("the snapshot states the instant and the weekday it was assembled for")
func snapshotCarriesTheClock() async {
    let snapshot = await assemble()

    #expect(snapshot["now"]?.stringValue == "2026-08-26T07:15:00-04:00")
    // The weekday is spelled out because a model reasoning about "the weekend" should not have to
    // derive it from a date, and deriving is where it would invent one.
    #expect(snapshot["dayOfWeek"]?.stringValue == "Wednesday")
}

@Test("the same instant and the same providers produce byte-identical JSON")
func assemblyIsDeterministic() async throws {
    let provider = MockMailProvider(messages: [message("One"), message("Two")])
    let events = MockCalendarProvider(events: [event("Standup", start: at(26, 9, 30))])

    let first = await DailyBriefAssembler(calendar: events, mail: provider, timeZone: zone).assemble(now: now)
    let second = await DailyBriefAssembler(calendar: events, mail: provider, timeZone: zone).assemble(now: now)

    // Not merely equal — identical once serialised. The prompt built from this is a prefix-cache
    // key, and a snapshot that reordered between runs would quietly cost the cache.
    #expect(try first.serialized() == second.serialized())
}

// MARK: - The window

@Test("the calendar is read from now to the end of tomorrow")
func windowSpansTwoDays() async throws {
    let provider = RecordingCalendarProvider(events: [])
    _ = await assemble(calendar: provider)

    let interval = try #require(await provider.requestedInterval)
    // Starts at `now`, not at midnight: a brief is about what is ahead, and this morning's 06:00
    // is not something to plan around at 07:15.
    #expect(interval.start == now)
    // Two full days out. The dashboard's own publisher reads now → end of TODAY, which is right for
    // a panel and wrong here: tomorrow's 08:00 is something to know about tonight.
    #expect(interval.end == at(28, 0))
}

@Test("events land in the day they occupy, and a multi-day event occupies both")
func eventsAreBucketedByOverlap() async {
    let snapshot = await assemble(calendar: MockCalendarProvider(events: [
        event("Investor call", start: at(26, 9, 30), end: at(26, 10, 15)),
        event("Dentist", start: at(27, 14), end: at(27, 14, 45)),
        event("Conference", start: at(26, 18), end: at(27, 17))
    ]))
    let calendar = section(snapshot, "calendar")

    #expect(calendar["state"]?.stringValue == "ready")
    #expect(rows(calendar, "today").compactMap { $0["title"]?.stringValue } == ["Investor call", "Conference"])
    // Bucketed by overlap rather than by start, so the conference running across midnight is
    // answered to someone asking what they have tomorrow.
    #expect(rows(calendar, "tomorrow").compactMap { $0["title"]?.stringValue } == ["Conference", "Dentist"])
}

@Test("an all-day event carries no clock time it does not have")
func allDayEventsHaveNoTime() async throws {
    let snapshot = await assemble(calendar: MockCalendarProvider(events: [
        event("Anna's birthday", start: at(26, 0), end: at(27, 0), allDay: true, calendarTitle: "Family")
    ]))

    let row = try #require(rows(section(snapshot, "calendar"), "today").first)
    #expect(row["allDay"] == .bool(true))
    // Rendering 00:00 would invent a precision the event does not have — "Birthday at midnight".
    #expect(row["start"] == nil)
    #expect(row["end"] == nil)
}

@Test("times are local wall clock in the assembler's own zone")
func timesUseTheInjectedZone() async throws {
    let snapshot = await assemble(calendar: MockCalendarProvider(events: [
        event("Investor call", start: at(26, 9, 30), end: at(26, 10, 15))
    ]))

    let row = try #require(rows(section(snapshot, "calendar"), "today").first)
    #expect(row["start"]?.stringValue == "09:30")
    #expect(row["end"]?.stringValue == "10:15")
    #expect(row["calendar"]?.stringValue == "Work")
}

@Test("a calendar description never reaches the model")
func calendarNotesAreNotCarried() async throws {
    // `notes` is read by the relevance resolver to find a `#[mode]` tag and is never surfaced. It
    // is free text on someone else's invitation: nothing in a brief needs it, and a model quoting
    // a meeting agenda back is a leak with no upside.
    let snapshot = await assemble(calendar: MockCalendarProvider(events: [
        event("1:1", start: at(26, 11), location: "", notes: "Discuss compensation and the reorg")
    ]))

    let row = try #require(rows(section(snapshot, "calendar"), "today").first)
    #expect(!row.keys.contains("notes"))
    #expect(try snapshot["calendar"].map { try $0.serialized() }.map {
        !String(decoding: $0, as: UTF8.self).contains("compensation")
    } == true)
    // An empty location is omitted rather than sent as "": the composer is told to use what is
    // present, and an empty string is something for it to dutifully mention.
    #expect(!row.keys.contains("location"))
}

// MARK: - Sources fail independently and say so

@Test("a denied calendar grant is stated, not rendered as an empty day")
func deniedCalendarIsStated() async {
    struct Denied: CalendarProvider {
        func events(within interval: DateInterval) async throws -> [CalendarEvent] {
            throw CalendarError.permissionDenied
        }
        func calendars() async throws -> [CalendarInfo] { throw CalendarError.permissionDenied }
    }

    let calendar = section(await assemble(calendar: Denied()), "calendar")
    #expect(calendar["state"]?.stringValue == "unavailable")
    // Specifically a grant, because that one the reader can actually fix.
    #expect(calendar["reason"]?.stringValue?.contains("access") == true)
    #expect(calendar["today"] == nil)
}

@Test("an absent provider reads the same as a failed one: nobody looked")
func absentProvidersAreUnavailable() async {
    let snapshot = await assemble(calendar: nil, mail: nil)

    #expect(section(snapshot, "calendar")["state"]?.stringValue == "unavailable")
    #expect(section(snapshot, "mail")["state"]?.stringValue == "unavailable")
}

@Test("one source failing leaves the other intact")
func sourcesFailIndependently() async {
    let snapshot = await assemble(
        calendar: MockCalendarProvider(error: .providerFailed("EventKit fell over")),
        mail: MockMailProvider(messages: [message("Invoice 4021")])
    )

    #expect(section(snapshot, "calendar")["state"]?.stringValue == "unavailable")
    #expect(section(snapshot, "mail")["state"]?.stringValue == "ready")
    #expect(rows(section(snapshot, "mail"), "recent").count == 1)
}

@Test("each way mail can fail says something different about what to do")
func mailFailuresAreDistinguished() async {
    async let notConnected = assemble(mail: MockMailProvider(error: .notConnected))
    async let expired = assemble(mail: MockMailProvider(error: .reconnectRequired))
    async let broken = assemble(mail: MockMailProvider(error: .providerFailed("500")))

    // Not connected, lapsed, and broken need three different things from the reader, and a single
    // "mail unavailable" would tell them none of it.
    #expect(section(await notConnected, "mail")["reason"]?.stringValue?.contains("connected") == true)
    #expect(section(await expired, "mail")["reason"]?.stringValue?.contains("renewing") == true)
    #expect(section(await broken, "mail")["reason"]?.stringValue?.contains("couldn\u{2019}t be read") == true)
}

// MARK: - Mail

@Test("the count comes from the summary, never from the length of the listing")
func countIsNotTheListingLength() async {
    // Counting rows would report "8 unread" for an inbox holding fifty. The real provider derives
    // both from one query for exactly this reason.
    let mail = MockMailProvider(
        messages: (1...8).map { message("Message \($0)") },
        summary: MailUnreadSummary(count: 51, isCapped: false, scope: .primary)
    )

    let section = section(await assemble(mail: mail), "mail")
    #expect(section["unreadTotal"] == .number(51))
    #expect(rows(section, "recent").count == 8)
    #expect(section["scope"]?.stringValue == "primary")
}

@Test("a capped count says so rather than passing off a ceiling as a total")
func cappedCountIsFlagged() async {
    let mail = MockMailProvider(
        messages: [message("One")],
        summary: MailUnreadSummary(count: 100, isCapped: true, scope: .inbox)
    )

    let section = section(await assemble(mail: mail), "mail")
    #expect(section["isCapped"] == .bool(true))
    // The whole inbox rather than the Primary tab — the difference between "three personal emails"
    // and "three including promotions".
    #expect(section["scope"]?.stringValue == "inbox")
}

@Test("a message arrives as a byline, a subject and a bounded preview")
func messagesCarryPreviews() async throws {
    let mail = MockMailProvider(messages: [
        message(
            "Invoice 4021",
            from: "Billing Team <billing@example.com>",
            preview: "Invoice 4021 is attached and due Friday."
        )
    ])

    let row = try #require(rows(section(await assemble(mail: mail), "mail"), "recent").first)
    // The byline, not the raw `From`. A brief reads as people, and the address itself is something
    // the model has no use for and no business holding.
    #expect(row["from"]?.stringValue == "Billing Team")
    #expect(!(row["from"]?.stringValue?.contains("@") ?? true))
    #expect(row["subject"]?.stringValue == "Invoice 4021")
    #expect(row["preview"]?.stringValue == "Invoice 4021 is attached and due Friday.")
}

@Test("a message with no preview simply has none")
func missingPreviewIsOmitted() async throws {
    let row = try #require(
        rows(section(await assemble(mail: MockMailProvider(messages: [message("Bare")])), "mail"), "recent").first
    )
    // Absent rather than empty: an empty string is a fact the composer would dutifully describe.
    #expect(!row.keys.contains("preview"))
}

@Test("a clear inbox is a stated zero, not a missing section")
func emptyInboxIsStated() async {
    let section = section(await assemble(mail: MockMailProvider(messages: [])), "mail")

    // "You are caught up" is worth saying, and only a stated zero lets the composer say it.
    #expect(section["state"]?.stringValue == "ready")
    #expect(section["unreadTotal"] == .number(0))
    #expect(rows(section, "recent").isEmpty)
}

@Test("no more than the preview budget of messages is carried")
func recentMailIsBounded() async {
    let mail = MockMailProvider(messages: (1...25).map { message("Message \($0)") })

    let section = section(await assemble(mail: mail), "mail")
    #expect(rows(section, "recent").count == DailyBriefAssembler.recentMailLimit)
}
