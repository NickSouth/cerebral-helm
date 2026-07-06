import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``ModeWorkspaceStore`` ("Windows Stored by Mode", NIC-85).
///
/// One row per mode; the snapshot is stored as a JSON array so it stays
/// inspectable. Saving replaces the mode's previous snapshot wholesale — a
/// snapshot describes "the workspace when this mode was last left", never a
/// merge.
///
/// Format compatibility: the column originally held a plain bundle-id array
/// (`["com.a.App", …]`); geometry restore enriched it to app objects with
/// optional frames. A legacy row loads as frame-less snapshots — user state is
/// upgraded on the next save, never silently dropped (FR-UPD-01 spirit).
public struct SQLiteModeWorkspaceStore: ModeWorkspaceStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func loadSnapshot(modeID: String) throws -> [WorkspaceAppSnapshot]? {
        guard
            let row = try database.query(
                "SELECT bundle_ids FROM mode_workspace_snapshots WHERE mode_id = ?;",
                [.text(modeID)]
            ).first,
            let json = row.text("bundle_ids")
        else { return nil }
        let data = Data(json.utf8)
        if let snapshots = try? JSONDecoder().decode([WorkspaceAppSnapshot].self, from: data) {
            return snapshots
        }
        // Legacy format (pre-geometry): a plain bundle-id array.
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            return legacy.map { WorkspaceAppSnapshot(bundleID: $0, frame: nil) }
        }
        return nil
    }

    public func saveSnapshot(modeID: String, apps: [WorkspaceAppSnapshot]) throws {
        let data = try JSONEncoder().encode(apps)
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
