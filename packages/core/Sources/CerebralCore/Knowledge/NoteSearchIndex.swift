import Foundation

/// One indexed note: the searchable projection of a Markdown file (FR-KNW-04).
/// Derived and disposable — rebuildable from the file (FR-KNW-06, NFR-09).
public struct NoteSearchIndexEntry: Equatable, Sendable {
    public let noteID: String
    public let path: String
    public let title: String?
    public let body: String?
    public let sensitivity: String?
    public let updated: Date?
    public let reviewAfter: Date?

    public init(
        noteID: String, path: String, title: String?, body: String?,
        sensitivity: String?, updated: Date?, reviewAfter: Date?
    ) {
        self.noteID = noteID
        self.path = path
        self.title = title
        self.body = body
        self.sensitivity = sensitivity
        self.updated = updated
        self.reviewAfter = reviewAfter
    }
}

/// The rebuildable note search index (FR-KNW-04/06, NFR-09).
///
/// A Core port so the durable knowledge service searches without importing a
/// storage implementation. The pre-Mac foundation binds a SQLite adapter
/// (`CerebralStorage.SQLiteNoteSearchIndex`); tests use ``InMemoryNoteSearchIndex``.
/// `matches` returns every note whose title, body, or path contains the query
/// (case-insensitive), in path order; the caller applies any limit and derives
/// freshness.
public protocol NoteSearchIndex: Sendable {
    func upsert(_ entry: NoteSearchIndexEntry) throws
    func matches(query: String) throws -> [NoteSearchIndexEntry]
    /// Drops the entire index (the derived state deleted before a rebuild).
    func deleteAll() throws
}

/// In-memory note search index for tests and as a default.
public final class InMemoryNoteSearchIndex: NoteSearchIndex, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: NoteSearchIndexEntry] = [:]

    public init() {}

    public func upsert(_ entry: NoteSearchIndexEntry) throws {
        lock.lock(); defer { lock.unlock() }
        entries[entry.noteID] = entry
    }

    public func matches(query: String) throws -> [NoteSearchIndexEntry] {
        lock.lock(); defer { lock.unlock() }
        let needle = query.lowercased()
        return entries.values
            .filter { entry in
                needle.isEmpty || "\(entry.title ?? "") \(entry.body ?? "") \(entry.path)"
                    .lowercased().contains(needle)
            }
            .sorted { $0.path < $1.path }
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}
