import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``CanvasHiddenStore`` (NIC-132).
///
/// The user's manually-hidden Canvas course/assignment ids are stored as one JSON array in a
/// single-row table (`id = 1`), replaced wholesale on each change. This lives separately from the
/// snapshot (which is replaced on every scrape), so a hidden item stays hidden after re-syncing. The
/// array is sorted before encoding so an identical set serialises to identical bytes.
public struct SQLiteCanvasHiddenStore: CanvasHiddenStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func hiddenIds() throws -> Set<String> {
        guard
            let row = try database.query("SELECT ids_json FROM canvas_hidden WHERE id = 1;").first,
            let json = row.text("ids_json"),
            let ids = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        else { return [] }
        return Set(ids)
    }

    public func setHiddenIds(_ ids: Set<String>) throws {
        let data = try JSONEncoder().encode(ids.sorted())
        _ = try database.run(
            """
            INSERT INTO canvas_hidden (id, ids_json, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                ids_json = excluded.ids_json,
                updated_at = excluded.updated_at;
            """,
            [.text(String(decoding: data, as: UTF8.self)), .timestamp(clock.now())]
        )
    }

    public func clear() throws {
        _ = try database.run("DELETE FROM canvas_hidden WHERE id = 1;")
    }
}
