-- Migration 0004: the durable user-settings singleton (FR-CFG-04).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. One row of independent nullable columns —
-- NULL means "never set" (config defaults apply); a patch touches only the
-- columns it carries.

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
