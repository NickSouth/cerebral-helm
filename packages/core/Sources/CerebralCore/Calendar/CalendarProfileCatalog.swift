import Foundation

/// The per-mode calendar relevance configuration (NIC-126), decoded from
/// `config/calendar/profiles.json`. It maps the four modes to their `calendarProfile` (the same
/// values the mode configs carry: executive→"all", developer→"engineering", school→"academic",
/// entertainment→"leisure"), names the default mode an event falls back to, and lists the `#[mode]`
/// tag aliases a user (or the future create-event tool) can write in an event's notes. Source
/// configuration lives here, not hardcoded in the resolver (FR-CFG), mirroring
/// ``NewsProfileCatalog``.
///
/// The **default mode's profile** is the catch-all: unresolved events fall to the default mode, so
/// its profile must show every event. That single fact defines the whole filtering rule (see
/// ``CalendarRelevanceResolver``) without hardcoding the literal "all".
public struct CalendarProfileCatalog: Decodable, Equatable, Sendable {
    /// The mode an event resolves to when it has neither a `#[mode]` tag nor a mapped calendar.
    public let defaultMode: String
    /// mode id → `calendarProfile` (the key the Today panel resolves `liveSchedule` by).
    public let modeProfiles: [String: String]
    /// lowercased `#[mode]` tag token → mode id (aliases; a raw mode id also resolves directly).
    public let tagAliases: [String: String]

    public init(defaultMode: String, modeProfiles: [String: String], tagAliases: [String: String]) {
        self.defaultMode = defaultMode
        self.modeProfiles = modeProfiles
        self.tagAliases = tagAliases
    }

    /// The distinct `calendarProfile` values across all modes, sorted for stable ordering. The
    /// producer fans out over exactly these — one `schedule.changed` per profile — so the Today
    /// panel finds a live region for whichever profile the active mode resolves to.
    public var distinctProfiles: [String] {
        Array(Set(modeProfiles.values)).sorted()
    }

    /// The `calendarProfile` for a mode id, or nil when the mode is unknown.
    public func profile(forMode mode: String) -> String? {
        modeProfiles[mode]
    }

    /// The catch-all profile — the default mode's profile — which shows every event. Nil only when
    /// the config is internally inconsistent (default mode absent from `modeProfiles`).
    public var catchAllProfile: String? {
        modeProfiles[defaultMode]
    }

    /// The mode a `#[mode]` tag token resolves to: an explicit alias first, else a raw mode id used
    /// directly as the tag (e.g. `#developer`), else nil. Case-insensitive.
    public func mode(forTag tag: String) -> String? {
        let key = tag.lowercased()
        if let aliased = tagAliases[key] {
            return aliased
        }
        return modeProfiles[key] != nil ? key : nil
    }

    /// Decodes a catalog from `config/calendar/profiles.json` bytes.
    public static func decode(from data: Data) throws -> CalendarProfileCatalog {
        try JSONDecoder().decode(CalendarProfileCatalog.self, from: data)
    }

    /// Loads the catalog from `<configDirectory>/calendar/profiles.json`, or nil when the file is
    /// absent or malformed — the caller degrades to an honest no-schedule state rather than
    /// crashing (mirrors ``NewsProfileCatalog/load(configDirectory:)``).
    public static func load(configDirectory: URL) -> CalendarProfileCatalog? {
        let url = configDirectory
            .appendingPathComponent("calendar", isDirectory: true)
            .appendingPathComponent("profiles.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(from: data)
    }
}
