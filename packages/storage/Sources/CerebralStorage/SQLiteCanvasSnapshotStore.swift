import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``CanvasSnapshotStore`` (NIC-132).
///
/// The latest Canvas scrape is stored as one inspectable JSON blob in a single-row table
/// (`id = 1`); saving replaces it wholesale — a snapshot is "the latest scrape", never a merge.
/// Scraped grades are personal data: they live only here, under the local state root, and are never
/// logged. Dates are encoded as ISO-8601 so the row stays human-readable, and keys are sorted so an
/// identical snapshot serialises to identical bytes.
public struct SQLiteCanvasSnapshotStore: CanvasSnapshotStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() throws -> CanvasScrapeSnapshot? {
        guard
            let row = try database.query(
                "SELECT snapshot_json FROM canvas_snapshot WHERE id = 1;"
            ).first,
            let json = row.text("snapshot_json")
        else { return nil }
        // A row we can't decode (e.g. an older shape) degrades to "no scrape yet" rather than
        // throwing — the widget shows its honest unavailable state and the next scrape heals it.
        return try? Self.makeDecoder().decode(CanvasScrapeSnapshot.self, from: Data(json.utf8))
    }

    public func save(_ snapshot: CanvasScrapeSnapshot) throws {
        let data = try Self.makeEncoder().encode(snapshot)
        _ = try database.run(
            """
            INSERT INTO canvas_snapshot (id, snapshot_json, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                snapshot_json = excluded.snapshot_json,
                updated_at = excluded.updated_at;
            """,
            [.text(String(decoding: data, as: UTF8.self)), .timestamp(clock.now())]
        )
    }

    public func clear() throws {
        _ = try database.run("DELETE FROM canvas_snapshot WHERE id = 1;")
    }
}
