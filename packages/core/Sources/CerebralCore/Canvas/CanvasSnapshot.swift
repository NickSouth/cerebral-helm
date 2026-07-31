import Foundation

/// One course scraped from the Canvas dashboard (NIC-132, School right slot). `percent` (0–100) is
/// the computed course score, omitted when Canvas has no score yet; `letterGrade` is Canvas's OWN
/// letter grade (never derived from the percent); `gradeHidden` marks a grade the user has hidden
/// in Canvas (shown honestly, never as a fabricated score). `code` is the short course code; `url`
/// is the course's Canvas home, backing the widget's click-to-open. Scraped personal data —
/// persisted only in the local store under the state root, never logged.
public struct CanvasCourse: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let code: String?
    /// Computed course score, 0–100. Omitted when Canvas has no score yet.
    public let percent: Double?
    /// Canvas's own letter grade. Omitted when Canvas shows none; never derived from `percent`.
    public let letterGrade: String?
    /// True when the user has hidden this grade in Canvas.
    public let gradeHidden: Bool
    /// The course's Canvas home URL, opened on click by the widget. Omitted when unknown.
    public let url: String?

    public init(
        id: String,
        name: String,
        code: String? = nil,
        percent: Double? = nil,
        letterGrade: String? = nil,
        gradeHidden: Bool = false,
        url: String? = nil
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.percent = percent
        self.letterGrade = letterGrade
        self.gradeHidden = gradeHidden
        self.url = url
    }
}

/// One upcoming assignment scraped from the Canvas dashboard (NIC-132, School left slot).
/// Submitted/completed work is excluded before an assignment ever reaches a snapshot. `dueAt` is the
/// local wall-clock ISO string of the due date/time (omitted when undated — the web formatters slice
/// components directly, per NIC-126); `courseName` is the owning course; `url` is the assignment's
/// Canvas URL, backing the widget's click-to-open. Scraped personal data — stored locally, never
/// logged.
public struct CanvasDeadline: Equatable, Sendable, Codable {
    public let id: String
    public let title: String
    /// Local wall-clock ISO of the due date/time. Omitted when the assignment has no due date.
    public let dueAt: String?
    public let courseName: String?
    /// The assignment's Canvas URL, opened on click by the widget. Omitted when unknown.
    public let url: String?

    public init(
        id: String,
        title: String,
        dueAt: String? = nil,
        courseName: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.courseName = courseName
        self.url = url
    }
}

/// The latest Canvas scrape (NIC-132): the courses and upcoming deadlines captured at `scrapedAt`
/// from `sourceURL`. Exactly one snapshot is kept — the newest scrape replaces the previous
/// wholesale — and `scrapedAt` drives the widget's "data age" line and the stale/unavailable
/// decision (applied by the read provider in a later increment).
public struct CanvasScrapeSnapshot: Equatable, Sendable, Codable {
    /// When the scrape was captured (second precision) — the basis for the freshness/staleness cue.
    public let scrapedAt: Date
    /// The Canvas page the scrape came from, if known. Diagnostic only — never surfaced verbatim.
    public let sourceURL: String?
    public let courses: [CanvasCourse]
    public let deadlines: [CanvasDeadline]

    public init(
        scrapedAt: Date,
        sourceURL: String? = nil,
        courses: [CanvasCourse],
        deadlines: [CanvasDeadline]
    ) {
        self.scrapedAt = scrapedAt
        self.sourceURL = sourceURL
        self.courses = courses
        self.deadlines = deadlines
    }
}

/// Port for the local Canvas scrape store (NIC-132). The Chrome-extension scrape is persisted here
/// (SQLite under the state root, ADR-006 operational state); the School widgets' producer reads the
/// latest snapshot. Losing the snapshot degrades to "no scrape yet", never an error. `clear()` backs
/// the disconnect purge. The concrete SQLite adapter lives in the storage package.
public protocol CanvasSnapshotStore: Sendable {
    /// The latest scrape, or `nil` when none has ever been stored.
    func load() throws -> CanvasScrapeSnapshot?
    /// Replaces the stored snapshot with the newest scrape (wholesale, never a merge).
    func save(_ snapshot: CanvasScrapeSnapshot) throws
    /// Removes the stored snapshot — the disconnect purge (a later increment).
    func clear() throws
}

/// Port for the manually-hidden Canvas items (NIC-132). The user can hide stray courses/assignments
/// from the School widgets; the ids persist across scrapes (kept separate from the wholesale-replaced
/// snapshot), so a hidden item stays hidden after re-syncing. `clear()` backs the disconnect reset.
public protocol CanvasHiddenStore: Sendable {
    /// The set of hidden course/assignment ids (empty when nothing is hidden).
    func hiddenIds() throws -> Set<String>
    /// Replaces the hidden set wholesale.
    func setHiddenIds(_ ids: Set<String>) throws
    /// Removes every hidden id (the disconnect reset).
    func clear() throws
}
