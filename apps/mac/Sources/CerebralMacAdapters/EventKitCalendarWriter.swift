// EventKit-backed calendar WRITE for the `create-event` Input (quick-actions phase 3). Separate
// from EventKitCalendarProvider, which only reads — the ports are distinct so a reader can never
// reach the write path.
#if canImport(EventKit)
@preconcurrency import EventKit
import Foundation
import CerebralTools

/// A ``CalendarWritingCapability`` over macOS EventKit.
///
/// A value type holding no state: it creates an ephemeral `EKEventStore` per write, matching
/// ``EventKitCalendarProvider``, so it is safe to share and holds no long-lived system handle.
///
/// Times arrive as local wall-clock ISO strings and are resolved in the host's **current** time
/// zone. That is deliberate: the user typed a time into a form on this machine, so the machine's
/// zone is the only interpretation that matches what they meant.
public struct EventKitCalendarWriter: CalendarWritingCapability {
    public init() {}

    public func createEvent(
        title: String,
        startsAt: String,
        endsAt: String,
        calendarID: String?,
        location: String?,
        notes: String?
    ) async throws -> (eventID: String, calendarTitle: String?) {
        guard let start = Self.date(from: startsAt), let end = Self.date(from: endsAt) else {
            throw NativeCapabilityError.adapterFailure("Could not read the event's start or end time.")
        }

        let store = EKEventStore()
        try await Self.requestWriteAccess(store)

        // An explicit calendar that no longer exists is an honest failure, not a silent write to
        // the default one — the user chose where this should go.
        let calendar: EKCalendar
        if let calendarID {
            guard let chosen = store.calendar(withIdentifier: calendarID) else {
                throw NativeCapabilityError.notFound("calendar \(calendarID)")
            }
            calendar = chosen
        } else {
            guard let fallback = store.defaultCalendarForNewEvents else {
                throw NativeCapabilityError.notFound("a default calendar")
            }
            calendar = fallback
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        event.location = location?.isEmpty == true ? nil : location
        event.notes = notes?.isEmpty == true ? nil : notes

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw NativeCapabilityError.adapterFailure("The calendar refused the event: \(error.localizedDescription)")
        }

        guard let identifier = event.eventIdentifier else {
            throw NativeCapabilityError.adapterFailure("The event was saved without an identifier.")
        }
        return (identifier, calendar.title)
    }

    /// Requests the narrowest grant that can create an event.
    ///
    /// Write-only is asked for first: creating an event does not require the ability to read the
    /// user's calendar, so this never escalates a machine that has only granted writing. An
    /// existing full-access grant satisfies it too — the read side may already have asked. A
    /// denial, a restriction, or a pre-14 system is an honest `permissionDenied`, which the tool
    /// surfaces as a failed command rather than a silent no-op.
    static func requestWriteAccess(_ store: EKEventStore) async throws {
        guard #available(macOS 14.0, *) else {
            throw NativeCapabilityError.permissionDenied
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return
        case .notDetermined:
            let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
            if !granted { throw NativeCapabilityError.permissionDenied }
        default:
            throw NativeCapabilityError.permissionDenied
        }
    }

    /// Parses `2026-08-03T14:00[:00]` as a wall-clock time in the host's current zone.
    static func date(from wallClock: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: wallClock) {
                return date
            }
        }
        return nil
    }
}
#endif
