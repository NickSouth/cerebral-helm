// EventKit-backed local calendar read for the Today panel (NIC-126). Reads every account the user
// has added to macOS Calendar (Google, iCloud, Exchange) with one local Calendar permission — no
// OAuth, no network. Gated so Linux CI compiles this target empty; live read is a manual smoke.
#if canImport(EventKit)
@preconcurrency import EventKit
import AppKit
import Foundation
import CerebralCore

/// A ``CalendarProvider`` over macOS EventKit (NIC-126). A value type holding no state: it creates
/// an ephemeral `EKEventStore` per fetch (like the ephemeral-`URLSession` HTTP providers), so it is
/// trivially `Sendable` for the port conformance. Access is requested **at point of use** — the
/// house rule for TCC permissions (the same one ``CoreLocationProvider`` follows): nothing is
/// requested at launch.
///
/// The `EKEvent → CalendarEvent` mapping is factored through the plain ``EventKitReading`` struct so
/// it is unit-testable without a live store; the live fetch itself is verified by manual smoke.
public struct EventKitCalendarProvider: CalendarProvider {
    public init() {}

    public func events(within interval: DateInterval) async throws -> [CalendarEvent] {
        let store = EKEventStore()
        try await Self.requestAccess(store)
        // A window predicate returns every event that OVERLAPS the range, so a multi-day event shows
        // on each day it spans and an all-day event shows on its day (owner rules) with no extra work.
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { Self.map(EventKitReading(from: $0)) }
    }

    public func calendars() async throws -> [CalendarInfo] {
        let store = EKEventStore()
        try await Self.requestAccess(store)
        // Title-sorted for a stable list in the Settings mapping UI; a blank title falls back to the
        // identifier so a row is never nameless.
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title.isEmpty ? calendar.calendarIdentifier : calendar.title,
                    colorHex: Self.colorHex(from: calendar.cgColor)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Ensures full calendar-read access, requesting it at point of use when undetermined. Full
    /// access is required even to *read* events on macOS 14+; a denied/restricted/write-only status
    /// (or an older system) is an honest ``CalendarError/permissionDenied`` the mapping degrades to
    /// "grant access in Settings". Never crashes, never fabricates.
    static func requestAccess(_ store: EKEventStore) async throws {
        guard #available(macOS 14.0, *) else {
            // Full-access read (requestFullAccessToEvents) is macOS 14+; degrade honestly on older.
            throw CalendarError.permissionDenied
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            if !granted { throw CalendarError.permissionDenied }
        default:
            // denied, restricted, or write-only cannot read events.
            throw CalendarError.permissionDenied
        }
    }

    /// Maps a read event into a portable ``CalendarEvent``, or nil to skip a degenerate one (no id,
    /// no start, or a blank title — an ad/placeholder row is dropped, never shown). `calendarId` /
    /// `calendarTitle` fall back to empty when EventKit omits the calendar (never fabricated).
    static func map(_ reading: EventKitReading) -> CalendarEvent? {
        guard
            let id = reading.eventIdentifier,
            let title = reading.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let start = reading.startDate
        else {
            return nil
        }
        return CalendarEvent(
            id: id,
            title: title,
            start: start,
            end: reading.endDate,
            isAllDay: reading.isAllDay,
            calendarId: reading.calendarIdentifier ?? "",
            calendarTitle: reading.calendarTitle ?? "",
            notes: reading.notes,
            location: reading.location?.isEmpty == false ? reading.location : nil,
            colorHex: reading.colorHex
        )
    }

    /// Converts a calendar's `CGColor` to `#rrggbb` in sRGB, or nil when it has no convertible
    /// colour. Carried for a future coloured dot; unused by the mapping this increment.
    static func colorHex(from cgColor: CGColor?) -> String? {
        guard let cgColor, let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return nil
        }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// The fields the mapping reads off one EventKit event — a plain struct so `EventKitCalendarProvider`
/// `.map(_:)` is testable without a live `EKEventStore`. The memberwise initializer serves tests; the
/// `init(from:)` extension serves the live read.
struct EventKitReading {
    let eventIdentifier: String?
    let title: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let notes: String?
    let location: String?
    let calendarIdentifier: String?
    let calendarTitle: String?
    let colorHex: String?
}

extension EventKitReading {
    init(from event: EKEvent) {
        self.init(
            eventIdentifier: event.eventIdentifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            notes: event.notes,
            location: event.location,
            calendarIdentifier: event.calendar?.calendarIdentifier,
            calendarTitle: event.calendar?.title,
            colorHex: EventKitCalendarProvider.colorHex(from: event.calendar?.cgColor)
        )
    }
}
#endif
