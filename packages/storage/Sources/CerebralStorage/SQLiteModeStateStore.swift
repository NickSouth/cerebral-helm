import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``ModeStateStore`` (FR-MOD-05).
///
/// Active mode and context are independent columns of a single row, persisted
/// **separately**: saving the mode leaves the context untouched and vice versa.
/// A missing row loads as `nil`, leaving the resolver to choose a safe default.
public struct SQLiteModeStateStore: ModeStateStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func loadActiveModeID() throws -> String? {
        try database.query("SELECT active_mode_id FROM mode_state WHERE id = 1;")
            .first?.text("active_mode_id")
    }

    public func saveActiveModeID(_ modeID: String?) throws {
        // Touches only the mode column; the context columns are preserved.
        try database.run(
            """
            INSERT INTO mode_state (id, active_mode_id, updated_at) VALUES (1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET active_mode_id = excluded.active_mode_id, updated_at = excluded.updated_at;
            """,
            [.textOrNull(modeID), .timestamp(clock.now())]
        )
    }

    public func loadActiveContext() throws -> ProjectContext? {
        guard
            let row = try database.query(
                "SELECT active_context_id, active_context_label FROM mode_state WHERE id = 1;"
            ).first,
            let id = row.text("active_context_id")
        else { return nil }
        return ProjectContext(id: id, label: row.text("active_context_label"))
    }

    public func saveActiveContext(_ context: ProjectContext?) throws {
        // Touches only the context columns; the mode column is preserved. Saving
        // `nil` clears the context (both columns NULL).
        try database.run(
            """
            INSERT INTO mode_state (id, active_context_id, active_context_label, updated_at) VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                active_context_id = excluded.active_context_id,
                active_context_label = excluded.active_context_label,
                updated_at = excluded.updated_at;
            """,
            [.textOrNull(context?.id), .textOrNull(context?.label), .timestamp(clock.now())]
        )
    }
}
