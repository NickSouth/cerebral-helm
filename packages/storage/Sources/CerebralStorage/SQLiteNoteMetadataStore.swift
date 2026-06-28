import Foundation
import CerebralCore

/// SQLite-backed ``NoteMetadataStore`` (FR-OBS-01 `note_metadata`).
///
/// Holds the rebuildable metadata index for captured notes; the Markdown file
/// remains the source of truth. `upsert` is keyed on `note_id`, so re-capturing or
/// rebuilding the same note replaces its row rather than duplicating it.
public struct SQLiteNoteMetadataStore: NoteMetadataStore {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func upsert(_ entry: NoteMetadataEntry) throws {
        try database.run(
            """
            INSERT INTO note_metadata
                (note_id, path, title, kind, project, sensitivity, cloud_policy, status, created_at, updated_at, review_after)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET
                path = excluded.path,
                title = excluded.title,
                kind = excluded.kind,
                project = excluded.project,
                sensitivity = excluded.sensitivity,
                cloud_policy = excluded.cloud_policy,
                status = excluded.status,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                review_after = excluded.review_after;
            """,
            [
                .text(entry.noteID),
                .text(entry.path),
                .textOrNull(entry.title),
                .textOrNull(entry.kind),
                .textOrNull(entry.project),
                .textOrNull(entry.sensitivity),
                .textOrNull(entry.cloudPolicy),
                .textOrNull(entry.status),
                entry.created.map(SQLiteValue.timestamp) ?? .null,
                entry.updated.map(SQLiteValue.timestamp) ?? .null,
                entry.reviewAfter.map(SQLiteValue.timestamp) ?? .null,
            ]
        )
    }

    public func get(noteID: String) throws -> NoteMetadataEntry? {
        let rows = try database.query(
            "\(Self.selectColumns) WHERE note_id = ?;", [.text(noteID)]
        )
        return rows.first.flatMap(Self.entry(from:))
    }

    public func all() throws -> [NoteMetadataEntry] {
        try database.query("\(Self.selectColumns) ORDER BY updated_at DESC, note_id;").compactMap(Self.entry(from:))
    }

    private static let selectColumns = """
    SELECT note_id, path, title, kind, project, sensitivity, cloud_policy, status, created_at, updated_at, review_after
    FROM note_metadata
    """

    private static func entry(from row: SQLiteRow) -> NoteMetadataEntry? {
        guard let noteID = row.text("note_id"), let path = row.text("path") else { return nil }
        return NoteMetadataEntry(
            noteID: noteID, path: path, title: row.text("title"), kind: row.text("kind"),
            project: row.text("project"), sensitivity: row.text("sensitivity"),
            cloudPolicy: row.text("cloud_policy"), status: row.text("status"),
            created: row.text("created_at").flatMap(StorageTimestamp.date(from:)),
            updated: row.text("updated_at").flatMap(StorageTimestamp.date(from:)),
            reviewAfter: row.text("review_after").flatMap(StorageTimestamp.date(from:))
        )
    }
}
