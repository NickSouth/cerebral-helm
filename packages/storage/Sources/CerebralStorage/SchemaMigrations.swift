/// The ordered registry of operational schema migrations (FR-OBS-01).
///
/// The SQL is embedded in Swift, not loaded from disk, so a OneDrive-dehydrated
/// `.sql` placeholder can never blank the schema at runtime, and the checksum is
/// taken over a source the compiler keeps hydrated. `database/migrations/*.sql`
/// holds a human-readable mirror that a test keeps in lockstep with these
/// constants. Moving the canonical source to bundled `.sql` resources is deferred
/// until resource bundling is validated on the macOS toolchain.
public enum SchemaMigrations {
    /// Every migration, in application order.
    public static let all: [SchemaMigration] = [
        SchemaMigration(id: "0001_initial", sql: initialSQL),
        SchemaMigration(id: "0002_mode_state", sql: modeStateSQL),
        SchemaMigration(id: "0003_note_search", sql: noteSearchSQL),
        SchemaMigration(id: "0004_settings", sql: settingsSQL),
        SchemaMigration(id: "0005_mode_workspace", sql: modeWorkspaceSQL),
        SchemaMigration(id: "0006_main_display", sql: mainDisplaySQL),
        SchemaMigration(id: "0007_assistant_name", sql: assistantNameSQL),
        SchemaMigration(id: "0008_mode_colors", sql: modeColorsSQL),
        SchemaMigration(id: "0009_confirm_all_actions", sql: confirmAllActionsSQL),
        SchemaMigration(id: "0010_layout_display", sql: layoutDisplaySQL),
    ]

    /// Operational schema, version 0001. Full note bodies stay authoritative in
    /// Markdown; this database stores operational and rebuildable derived state.
    public static let initialSQL = """
    -- Operational schema 0001 (PRE-DATA-4 / FR-OBS-01).
    -- Full note bodies remain authoritative in Markdown; this database stores
    -- operational history and rebuildable derived state only.

    CREATE TABLE commands (
        id             TEXT PRIMARY KEY,
        source         TEXT NOT NULL,
        redacted_input TEXT,
        sensitivity    TEXT,
        cloud_policy   TEXT,
        status         TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL
    );
    CREATE INDEX idx_commands_created_at ON commands (created_at);
    CREATE INDEX idx_commands_status ON commands (status);

    CREATE TABLE command_events (
        id              TEXT PRIMARY KEY,
        command_id      TEXT NOT NULL REFERENCES commands (id) ON DELETE CASCADE,
        status          TEXT NOT NULL,
        previous_status TEXT,
        occurred_at     TEXT NOT NULL,
        payload         TEXT
    );
    CREATE INDEX idx_command_events_command_id ON command_events (command_id);
    CREATE INDEX idx_command_events_occurred_at ON command_events (occurred_at);

    CREATE TABLE tool_calls (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        command_id      TEXT NOT NULL REFERENCES commands (id) ON DELETE CASCADE,
        tool_id         TEXT NOT NULL,
        tool_version    TEXT NOT NULL,
        adapter_id      TEXT NOT NULL,
        status          TEXT NOT NULL,
        duration_ms     INTEGER,
        started_at      TEXT NOT NULL,
        completed_at    TEXT NOT NULL,
        redacted_input  TEXT,
        redacted_output TEXT,
        error_category  TEXT,
        error_code      TEXT,
        error_message   TEXT
    );
    CREATE INDEX idx_tool_calls_command_id ON tool_calls (command_id);
    CREATE INDEX idx_tool_calls_tool_id ON tool_calls (tool_id);

    -- One pending confirmation per command (mirrors the in-memory coordinator map).
    -- expires_at and used are persisted so the single-use / expiry guards
    -- (FR-SAF-05) survive a process restart (NIC-112).
    CREATE TABLE confirmations (
        command_id      TEXT PRIMARY KEY,
        confirmation_id TEXT NOT NULL,
        token_value     TEXT NOT NULL,
        plan_hash       TEXT NOT NULL,
        expires_at      TEXT NOT NULL,
        used            INTEGER NOT NULL DEFAULT 0,
        decision        TEXT,
        created_at      TEXT NOT NULL
    );
    CREATE INDEX idx_confirmations_expires_at ON confirmations (expires_at);

    CREATE TABLE note_metadata (
        note_id      TEXT PRIMARY KEY,
        path         TEXT NOT NULL,
        title        TEXT,
        kind         TEXT,
        project      TEXT,
        sensitivity  TEXT,
        cloud_policy TEXT,
        status       TEXT,
        created_at   TEXT,
        updated_at   TEXT,
        review_after TEXT
    );
    CREATE INDEX idx_note_metadata_project ON note_metadata (project);
    CREATE INDEX idx_note_metadata_updated_at ON note_metadata (updated_at);

    CREATE TABLE mode_sessions (
        id             TEXT PRIMARY KEY,
        mode_id        TEXT NOT NULL,
        context_id     TEXT,
        context_label  TEXT,
        source         TEXT NOT NULL,
        started_at     TEXT NOT NULL,
        ended_at       TEXT,
        result         TEXT NOT NULL,
        config_version TEXT NOT NULL
    );
    CREATE INDEX idx_mode_sessions_started_at ON mode_sessions (started_at);
    CREATE INDEX idx_mode_sessions_mode_id ON mode_sessions (mode_id);

    CREATE TABLE settings_metadata (
        id                      INTEGER PRIMARY KEY AUTOINCREMENT,
        active_config_version   TEXT NOT NULL,
        last_known_good_version TEXT,
        applied_migrations      TEXT,
        recorded_at             TEXT NOT NULL
    );
    CREATE INDEX idx_settings_metadata_recorded_at ON settings_metadata (recorded_at);

    CREATE TABLE updates (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        from_version TEXT,
        to_version   TEXT,
        channel      TEXT,
        stage        TEXT,
        status       TEXT NOT NULL,
        message      TEXT,
        recorded_at  TEXT NOT NULL
    );
    CREATE INDEX idx_updates_recorded_at ON updates (recorded_at);
    """

    /// Migration 0002: the active-mode/context singleton (FR-MOD-05). Mode and
    /// context are independent columns of one row so either can change or fall back
    /// without disturbing the other.
    public static let modeStateSQL = """
    CREATE TABLE mode_state (
        id                   INTEGER PRIMARY KEY CHECK (id = 1),
        active_mode_id       TEXT,
        active_context_id    TEXT,
        active_context_label TEXT,
        updated_at           TEXT NOT NULL
    );
    """

    /// Migration 0003: the rebuildable note search index (FR-KNW-04/06, NFR-09).
    /// A disposable derived projection of each note's searchable text; the Markdown
    /// file stays authoritative, so this table can be dropped and rebuilt from disk.
    public static let noteSearchSQL = """
    CREATE TABLE note_search (
        note_id      TEXT PRIMARY KEY,
        path         TEXT NOT NULL,
        title        TEXT,
        body         TEXT,
        sensitivity  TEXT,
        updated_at   TEXT,
        review_after TEXT
    );
    CREATE INDEX idx_note_search_path ON note_search (path);
    """

    /// Migration 0004: the durable user-settings singleton (FR-CFG-04). One row of
    /// independent nullable columns — NULL means "never set", so config defaults
    /// still apply; a patch touches only the columns it carries.
    public static let settingsSQL = """
    CREATE TABLE settings (
        id                        INTEGER PRIMARY KEY CHECK (id = 1),
        default_mode_id           TEXT,
        appearance_density        TEXT,
        appearance_reduced_motion INTEGER,
        hotkey_command_palette    TEXT,
        knowledge_root_reference  TEXT,
        extensions                TEXT,
        updated_at                TEXT NOT NULL
    );
    """

    /// Migration 0005: "Windows Stored by Mode" (NIC-85). The settings singleton
    /// gains the toggle column, and per-mode workspace snapshots store the bundle
    /// ids of the applications visible when the mode was last left.
    public static let modeWorkspaceSQL = """
    ALTER TABLE settings ADD COLUMN windows_stored_by_mode INTEGER;

    CREATE TABLE mode_workspace_snapshots (
        mode_id    TEXT PRIMARY KEY,
        bundle_ids TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    """

    /// Migration 0006: the "Main display" setting (NIC-120b). The settings
    /// singleton gains the stable display id the main dashboard backdrop is
    /// hosted on; NULL or a disconnected/unknown id degrades to the system
    /// primary display.
    public static let mainDisplaySQL = """
    ALTER TABLE settings ADD COLUMN main_display_id TEXT;
    """

    /// Migration 0007: the "Assistant Name" setting (NIC-137). The settings
    /// singleton gains the assistant's display name shown across the dashboard;
    /// NULL means the default identity (`Heimlich`) applies.
    public static let assistantNameSQL = """
    ALTER TABLE settings ADD COLUMN appearance_assistant_name TEXT;
    """

    /// Migration 0008: per-mode accent color overrides (NIC-137). The settings
    /// singleton gains a JSON map of design-token name (e.g. `executive.primary`)
    /// to a `#rrggbb` hex value; NULL means no overrides, so every mode uses its
    /// shipped palette.
    public static let modeColorsSQL = """
    ALTER TABLE settings ADD COLUMN mode_colors TEXT;
    """

    /// Migration 0009: the "Ask before all actions" tightening (NIC-137). The
    /// settings singleton gains a flag that, when set, raises every non-read-only
    /// action to require confirmation; NULL/0 = descriptor policy governs.
    public static let confirmAllActionsSQL = """
    ALTER TABLE settings ADD COLUMN confirm_all_actions INTEGER;
    """

    /// Migration 0010: the "Layout display" setting (NIC-142). The settings
    /// singleton gains the stable display id layout mode opens on (and whose bottom
    /// bar shows the hotswap pill); NULL or a disconnected/unknown id degrades to
    /// the main display, then the system primary — the shell never errors on it.
    public static let layoutDisplaySQL = """
    ALTER TABLE settings ADD COLUMN layout_display_id TEXT;
    """
}
