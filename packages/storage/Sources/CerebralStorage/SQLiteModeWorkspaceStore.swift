import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``ModeWorkspaceStore`` ("Windows Stored by Mode", NIC-85).
///
/// One row per mode; the bundle-id list is stored as a JSON array so the snapshot
/// stays inspectable. Saving replaces the mode's previous snapshot wholesale — a
/// snapshot describes "the workspace when this mode was last left", never a merge.
public struct SQLiteModeWorkspaceStore: ModeWorkspaceStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func loadSnapshot(modeID: String) throws -> [String]? {
        guard
            let row = try database.query(
                "SELECT bundle_ids FROM mode_workspace_snapshots WHERE mode_id = ?;",
                [.text(modeID)]
            ).first,
            let json = row.text("bundle_ids"),
            let decoded = try? JSONDecoder().decode([String].self, from: Data(json.utf8))
        else { return nil }
        return decoded
    }

    public func saveSnapshot(modeID: String, bundleIDs: [String]) throws {
        let data = try JSONEncoder().encode(bundleIDs)
        try database.run(
            """
            INSERT INTO mode_workspace_snapshots (mode_id, bundle_ids, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(mode_id) DO UPDATE SET
                bundle_ids = excluded.bundle_ids,
                updated_at = excluded.updated_at;
            """,
            [.text(modeID), .text(String(decoding: data, as: UTF8.self)), .timestamp(clock.now())]
        )
    }
}
