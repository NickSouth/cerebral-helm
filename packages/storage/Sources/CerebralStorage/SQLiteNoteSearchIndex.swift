import Foundation
import CerebralCore

/// SQLite-backed ``NoteSearchIndex`` (FR-KNW-04/06, NFR-09).
///
/// A disposable derived projection of the note corpus, queried with a
/// case-insensitive `LIKE` over title + body + path. The Markdown files remain the
/// source of truth, so ``deleteAll`` + re-`upsert` (rebuild) reconstructs the index
/// without data loss.
public struct SQLiteNoteSearchIndex: NoteSearchIndex {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsert(_ entry: NoteSearchIndexEntry) throws {
        try database.run(
            """
            INSERT INTO note_search (note_id, path, title, body, sensitivity, updated_at, review_after)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
                path = excluded.path,
                title = excluded.title,
                body = excluded.body,
                sensitivity = excluded.sensitivity,
                updated_at = excluded.updated_at,
                review_after = excluded.review_after;
            """,
            [
                .text(entry.noteID),
                .text(entry.path),
                .textOrNull(entry.title),
                .textOrNull(entry.body),
                .textOrNull(entry.sensitivity),
                entry.updated.map(SQLiteValue.timestamp) ?? .null,
                entry.reviewAfter.map(SQLiteValue.timestamp) ?? .null,
            ]
        )
    }

    public func matches(query: String) throws -> [NoteSearchIndexEntry] {
        let pattern = "%\(Self.escapeLike(query.lowercased()))%"
        let rows = try database.query(
            """
            SELECT note_id, path, title, body, sensitivity, updated_at, review_after
            FROM note_search
            WHERE lower(coalesce(title, '') || ' ' || coalesce(body, '') || ' ' || path) LIKE ? ESCAPE '\\'
            ORDER BY path, note_id;
            """,
            [.text(pattern)]
        )
        return rows.compactMap(Self.entry(from:))
    }

    public func deleteAll() throws {
        try database.run("DELETE FROM note_search;")
    }

    /// Escapes `LIKE` metacharacters so a query term is matched literally.
    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func entry(from row: SQLiteRow) -> NoteSearchIndexEntry? {
        guard let noteID = row.text("note_id"), let path = row.text("path") else { return nil }
        return NoteSearchIndexEntry(
            noteID: noteID, path: path, title: row.text("title"), body: row.text("body"),
            sensitivity: row.text("sensitivity"),
            updated: row.text("updated_at").flatMap(StorageTimestamp.date(from:)),
            reviewAfter: row.text("review_after").flatMap(StorageTimestamp.date(from:))
        )
    }
}
