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
            confirmAllActions: row.integer("confirm_all_actions").map { $0 != 0 },
            appearanceDensity: row.text("appearance_density"),
            appearanceReducedMotion: row.integer("appearance_reduced_motion").map { $0 != 0 },
            appearanceAssistantName: row.text("appearance_assistant_name"),
            commandPaletteHotkey: row.text("hotkey_command_palette"),
            knowledgeRootReference: row.text("knowledge_root_reference"),
            windowsStoredByMode: row.integer("windows_stored_by_mode").map { $0 != 0 },
            mainDisplayID: row.text("main_display_id"),
            layoutDisplayID: row.text("layout_display_id"),
            modeColorsJSON: row.text("mode_colors"),
            extensionsJSON: row.text("extensions"),
            stockTickersJSON: row.text("stock_tickers"),
            calendarModeMapJSON: row.text("calendar_mode_map")
        )
    }

    public func apply(_ changes: SettingsChanges) throws {
        try database.run(
            """
            INSERT INTO settings (
                id, default_mode_id, confirm_all_actions, appearance_density, appearance_reduced_motion,
                appearance_assistant_name, hotkey_command_palette, knowledge_root_reference,
                windows_stored_by_mode, main_display_id, layout_display_id, mode_colors, extensions,
                stock_tickers, calendar_mode_map, updated_at
            ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                default_mode_id           = COALESCE(excluded.default_mode_id, default_mode_id),
                confirm_all_actions       = COALESCE(excluded.confirm_all_actions, confirm_all_actions),
                appearance_density        = COALESCE(excluded.appearance_density, appearance_density),
                appearance_reduced_motion = COALESCE(excluded.appearance_reduced_motion, appearance_reduced_motion),
                appearance_assistant_name = COALESCE(excluded.appearance_assistant_name, appearance_assistant_name),
                hotkey_command_palette    = COALESCE(excluded.hotkey_command_palette, hotkey_command_palette),
                knowledge_root_reference  = COALESCE(excluded.knowledge_root_reference, knowledge_root_reference),
                windows_stored_by_mode    = COALESCE(excluded.windows_stored_by_mode, windows_stored_by_mode),
                main_display_id           = COALESCE(excluded.main_display_id, main_display_id),
                layout_display_id         = COALESCE(excluded.layout_display_id, layout_display_id),
                mode_colors               = COALESCE(excluded.mode_colors, mode_colors),
                extensions                = COALESCE(excluded.extensions, extensions),
                stock_tickers             = COALESCE(excluded.stock_tickers, stock_tickers),
                calendar_mode_map         = COALESCE(excluded.calendar_mode_map, calendar_mode_map),
                updated_at                = excluded.updated_at;
            """,
            [
                .textOrNull(changes.defaultModeID),
                changes.confirmAllActions.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null,
                .textOrNull(changes.appearanceDensity),
                changes.appearanceReducedMotion.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null,
                .textOrNull(changes.appearanceAssistantName),
                .textOrNull(changes.commandPaletteHotkey),
                .textOrNull(changes.knowledgeRootReference),
                changes.windowsStoredByMode.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null,
                .textOrNull(changes.mainDisplayID),
                .textOrNull(changes.layoutDisplayID),
                .textOrNull(changes.modeColorsJSON),
                .textOrNull(changes.extensionsJSON),
                .textOrNull(changes.stockTickersJSON),
                .textOrNull(changes.calendarModeMapJSON),
                .timestamp(clock.now()),
            ]
        )
    }
}
