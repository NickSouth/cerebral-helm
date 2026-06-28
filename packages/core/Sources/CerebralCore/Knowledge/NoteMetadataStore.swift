import Foundation

/// The durable, derived metadata for one captured note (FR-OBS-01 `note_metadata`).
///
/// The Markdown file is the source of truth; this row is rebuildable from it
/// (FR-KNW-06), so every field except the identity (`noteID`, `path`) is optional —
/// a rebuild from a partial or hand-edited note must still produce a row.
public struct NoteMetadataEntry: Equatable, Sendable {
    public let noteID: String
    public let path: String
    public let title: String?
    public let kind: String?
    public let project: String?
    public let sensitivity: String?
    public let cloudPolicy: String?
    public let status: String?
    public let created: Date?
    public let updated: Date?
    public let reviewAfter: Date?

    public init(
        noteID: String, path: String, title: String?, kind: String?, project: String?,
        sensitivity: String?, cloudPolicy: String?, status: String?,
        created: Date?, updated: Date?, reviewAfter: Date?
    ) {
        self.noteID = noteID
        self.path = path
        self.title = title
        self.kind = kind
        self.project = project
        self.sensitivity = sensitivity
        self.cloudPolicy = cloudPolicy
        self.status = status
        self.created = created
        self.updated = updated
        self.reviewAfter = reviewAfter
    }
}

/// Persists derived note metadata. The durable Markdown note is authoritative;
/// this is the rebuildable index row.
///
/// A Core port so the durable knowledge service depends on it without importing a
/// storage implementation. The pre-Mac foundation binds a SQLite adapter
/// (`CerebralStorage.SQLiteNoteMetadataStore`); tests use ``InMemoryNoteMetadataStore``.
public protocol NoteMetadataStore: Sendable {
    func upsert(_ entry: NoteMetadataEntry) throws
    func get(noteID: String) throws -> NoteMetadataEntry?
    func all() throws -> [NoteMetadataEntry]
}

/// In-memory note-metadata store for tests and as a default.
public final class InMemoryNoteMetadataStore: NoteMetadataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: NoteMetadataEntry] = [:]

    public init() {}

    public func upsert(_ entry: NoteMetadataEntry) throws {
        lock.lock(); defer { lock.unlock() }
        entries[entry.noteID] = entry
    }

    public func get(noteID: String) throws -> NoteMetadataEntry? {
        lock.lock(); defer { lock.unlock() }
        return entries[noteID]
    }

    public func all() throws -> [NoteMetadataEntry] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.values)
    }
}
