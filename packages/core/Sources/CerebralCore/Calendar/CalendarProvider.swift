import Foundation

/// A single calendar event for the top-left Today panel (NIC-126). Produced by a
/// ``CalendarProvider`` and mapped to a `DashboardScheduleRegion` by the event mapping (this
/// increment) / the live producer (Increment 5). Provider-neutral: the fields are exactly what
/// every calendar source (macOS EventKit for the MVP, a future Google adapter) can supply.
///
/// `notes` carries the event's description text — the only place the layered relevance resolver
/// reads it, to find a `#[mode]` tag; it is never emitted to the dashboard or logged. `calendarId`
/// / `calendarTitle` identify the source calendar so the resolver can map it to a mode. `colorHex`
/// is the source calendar's colour when known, carried for a future coloured dot (unused this
/// increment). Optional fields are omitted, never fabricated.
public struct CalendarEvent: Equatable, Sendable {
    /// Stable per-event id, used as the dashboard row key.
    public let id: String
    /// The event title (summary).
    public let title: String
    /// The event's start instant (absolute; the mapping renders it in the local time zone).
    public let start: Date
    /// The event's end instant, when known.
    public let end: Date?
    /// Whether the event is all-day (owner rule: an all-day event maps to the `today` kind).
    public let isAllDay: Bool
    /// The source calendar's stable identifier — the key the calendar→mode mapping is keyed on.
    public let calendarId: String
    /// The source calendar's display title (e.g. "Work", "Family").
    public let calendarTitle: String
    /// The event's description/notes, read only to resolve a `#[mode]` tag; never surfaced.
    public let notes: String?
    /// The event's location, surfaced as a hover tooltip on the row (NIC-126); nil when unset.
    public let location: String?
    /// The source calendar's colour as `#rrggbb`, when known (carried for a future coloured dot).
    public let colorHex: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        calendarId: String,
        calendarTitle: String,
        notes: String? = nil,
        location: String? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarId = calendarId
        self.calendarTitle = calendarTitle
        self.notes = notes
        self.location = location
        self.colorHex = colorHex
    }
}

/// One of the user's calendars (NIC-126), for the Settings calendar→mode mapping UI. `id` is the
/// stable identifier the mapping is keyed on; `colorHex` is the calendar's colour when known (for a
/// swatch), omitted rather than fabricated.
public struct CalendarInfo: Equatable, Sendable {
    public let id: String
    public let title: String
    public let colorHex: String?

    public init(id: String, title: String, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
    }
}

/// Why a calendar fetch could not be produced. Kept coarse and provider-neutral: the event mapping
/// degrades any failure to an honest `unavailable` region, distinguishing only a denied permission
/// (so the panel can guide the user to grant Calendar access) from a provider/read failure. FR-SAF-07:
/// a missing grant becomes honest guidance, never a fabricated schedule.
public enum CalendarError: Error, Equatable, Sendable {
    /// Calendar access has not been granted — the panel should guide the user to grant it.
    case permissionDenied
    /// The calendar source failed, or returned events that could not be read.
    case providerFailed(String)
}

/// Port that fetches the events within a time window (NIC-126). Provider-neutral: the caller (the
/// ``CalendarProvider``'s live producer, Increment 5) passes the window, and a concrete provider
/// (macOS EventKit, Increment 3) reads its own store. Async because a real provider performs a
/// system/network read; the mock resolves synchronously. Throws ``CalendarError`` on failure — the
/// mapping treats it as an honest `unavailable`, never a made-up list.
public protocol CalendarProvider: Sendable {
    func events(within interval: DateInterval) async throws -> [CalendarEvent]
    /// The user's calendars, for the Settings mapping UI (NIC-126). Throws ``CalendarError`` when
    /// access is denied — the Settings surface then shows an honest "grant access" state.
    func calendars() async throws -> [CalendarInfo]
}

/// A fixed-outcome ``CalendarProvider`` for pre-Mac builds and tests: it ignores the interval and
/// always yields the events (or throws the error) it was constructed with.
public struct MockCalendarProvider: CalendarProvider {
    private let outcome: Result<[CalendarEvent], CalendarError>
    private let calendarsOutcome: Result<[CalendarInfo], CalendarError>

    public init(events: [CalendarEvent], calendars: [CalendarInfo] = []) {
        self.outcome = .success(events)
        self.calendarsOutcome = .success(calendars)
    }

    public init(error: CalendarError) {
        self.outcome = .failure(error)
        self.calendarsOutcome = .failure(error)
    }

    public func events(within interval: DateInterval) async throws -> [CalendarEvent] {
        try outcome.get()
    }

    public func calendars() async throws -> [CalendarInfo] {
        try calendarsOutcome.get()
    }
}
