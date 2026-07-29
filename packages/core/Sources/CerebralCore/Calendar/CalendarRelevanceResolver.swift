import Foundation

/// The deterministic layered relevance resolver (NIC-126) — the categorisation heart, outside any
/// model (Engineering Principles: risk/relevance classification is deterministic). Given a
/// ``CalendarProfileCatalog`` and the user's calendar→mode mapping, it resolves each event to a
/// target mode, then to that mode's `calendarProfile`, and filters a set of events down to a
/// profile.
///
/// Resolution order per event: (1) an explicit `#[mode]` tag in the notes wins; (2) else the event's
/// calendar→mode mapping; (3) else the catalog's default mode. Filtering: the catch-all profile
/// (the default mode's profile) shows every event; any other profile shows only events whose
/// resolved profile equals it. So the default mode (Executive) is an overview that never hides an
/// event, while each other mode sees only its slice.
public struct CalendarRelevanceResolver: Sendable {
    private let catalog: CalendarProfileCatalog
    /// calendar identifier → mode id (the durable user mapping, Increment 4; empty until then).
    private let calendarModeMap: [String: String]

    public init(catalog: CalendarProfileCatalog, calendarModeMap: [String: String] = [:]) {
        self.catalog = catalog
        self.calendarModeMap = calendarModeMap
    }

    /// The target mode for an event: a `#[mode]` tag in the notes wins, else the event's
    /// calendar→mode mapping, else the catalog default mode.
    public func mode(for event: CalendarEvent) -> String {
        if let tagged = taggedMode(in: event.notes) {
            return tagged
        }
        if let mapped = calendarModeMap[event.calendarId] {
            return mapped
        }
        return catalog.defaultMode
    }

    /// The `calendarProfile` an event belongs to — its resolved mode's profile, falling back to the
    /// default mode's profile if that mode has no configured profile (never nil-propagates: an event
    /// always lands in some profile).
    public func profile(for event: CalendarEvent) -> String {
        let resolvedMode = mode(for: event)
        return catalog.profile(forMode: resolvedMode)
            ?? catalog.catchAllProfile
            ?? resolvedMode
    }

    /// The events to show for one `calendarProfile`: the catch-all profile (the default mode's
    /// profile) shows every event; any other profile shows only events whose resolved profile
    /// equals it. Order is preserved.
    public func events(forProfile targetProfile: String, from events: [CalendarEvent]) -> [CalendarEvent] {
        if targetProfile == catalog.catchAllProfile {
            return events
        }
        return events.filter { profile(for: $0) == targetProfile }
    }

    /// Scans the notes for the first `#token` that resolves to a known mode. A `#` followed by
    /// letters/digits is a tag; the first that maps (via alias or a raw mode id) wins. Robust to a
    /// lone `#` and to tags embedded mid-text; case-insensitive.
    private func taggedMode(in notes: String?) -> String? {
        guard let notes, notes.contains("#") else { return nil }
        let characters = Array(notes)
        var index = 0
        while index < characters.count {
            guard characters[index] == "#" else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, characters[end].isLetter || characters[end].isNumber {
                end += 1
            }
            if end > index + 1 {
                let token = String(characters[(index + 1)..<end])
                if let mode = catalog.mode(forTag: token) {
                    return mode
                }
            }
            index = max(end, index + 1)
        }
        return nil
    }
}
