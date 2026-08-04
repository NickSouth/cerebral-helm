import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``NewsCacheStore`` (the news quota fix).
///
/// The whole cache — every profile's last known headlines plus the last attempt time — is stored
/// as one inspectable JSON blob in a single-row table (`id = 1`), mirroring
/// ``SQLiteCanvasSnapshotStore``. Saving replaces it wholesale; the cache is always "the latest
/// tick", never a merge.
///
/// This is rebuildable derived state, not user data: a row that cannot be decoded (an older shape)
/// degrades to "no cache yet" rather than throwing, which costs one extra provider request and
/// heals on the next successful fetch. Headlines are public content and hold no secret — the API
/// token lives in the Keychain and never reaches this table.
public struct SQLiteNewsCacheStore: NewsCacheStore {
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

    public func load() throws -> NewsCacheSnapshot? {
        guard
            let row = try database.query(
                "SELECT cache_json FROM news_cache WHERE id = 1;"
            ).first,
            let json = row.text("cache_json")
        else { return nil }
        return try? Self.makeDecoder().decode(NewsCacheSnapshot.self, from: Data(json.utf8))
    }

    public func save(_ snapshot: NewsCacheSnapshot) throws {
        let data = try Self.makeEncoder().encode(snapshot)
        _ = try database.run(
            """
            INSERT INTO news_cache (id, cache_json, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                cache_json = excluded.cache_json,
                updated_at = excluded.updated_at;
            """,
            [.text(String(decoding: data, as: UTF8.self)), .timestamp(clock.now())]
        )
    }
}
