import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``SettingsStore`` (FR-CFG-04, ADR-006).
///
/// One singleton row of independent nullable columns. `apply` is a single upsert
/// that COALESCEs each absent patch field back to the stored value, so a partial
/// patch never disturbs unrelated settings and the write is atomic — the patch
/// contract has no clear/reset semantics, so a stored value can only be replaced,
/// never nulled.
public struct SQLiteSettingsStore: SettingsStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func load() throws -> StoredSettings {
        guard let row = try database.query("SELECT * FROM settings WHERE id = 1;").first else {
            return StoredSettings()
        }
        return StoredSettings(
            defaultModeID: row.text("default_mode_id"),
            appearanceDensity: row.text("appearance_density"),
            appearanceReducedMotion: row.integer("appearance_reduced_motion").map { $0 != 0 },
            commandPaletteHotkey: row.text("hotkey_command_palette"),
            knowledgeRootReference: row.text("knowledge_root_reference"),
            windowsStoredByMode: row.integer("windows_stored_by_mode").map { $0 != 0 },
            mainDisplayID: row.text("main_display_id"),
            extensionsJSON: row.text("extensions")
        )
    }

    public func apply(_ changes: SettingsChanges) throws {
        try database.run(
            """
            INSERT INTO settings (
                id, default_mode_id, appearance_density, appearance_reduced_motion,
                hotkey_command_palette, knowledge_root_reference, windows_stored_by_mode,
                main_display_id, extensions, updated_at
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                default_mode_id           = COALESCE(excluded.default_mode_id, default_mode_id),
                appearance_density        = COALESCE(excluded.appearance_density, appearance_density),
                appearance_reduced_motion = COALESCE(excluded.appearance_reduced_motion, appearance_reduced_motion),
                hotkey_command_palette    = COALESCE(excluded.hotkey_command_palette, hotkey_command_palette),
                knowledge_root_reference  = COALESCE(excluded.knowledge_root_reference, knowledge_root_reference),
                windows_stored_by_mode    = COALESCE(excluded.windows_stored_by_mode, windows_stored_by_mode),
                main_display_id           = COALESCE(excluded.main_display_id, main_display_id),
                extensions                = COALESCE(excluded.extensions, extensions),
                updated_at                = excluded.updated_at;
            """,
            [
                .textOrNull(changes.defaultModeID),
                .textOrNull(changes.appearanceDensity),
                changes.appearanceReducedMotion.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null,
                .textOrNull(changes.commandPaletteHotkey),
                .textOrNull(changes.knowledgeRootReference),
                changes.windowsStoredByMode.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null,
                .textOrNull(changes.mainDisplayID),
                .textOrNull(changes.extensionsJSON),
                .timestamp(clock.now()),
            ]
        )
    }
}
