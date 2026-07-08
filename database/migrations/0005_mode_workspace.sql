-- Migration 0005: "Windows Stored by Mode" (NIC-85).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains the toggle
-- column, and per-mode workspace snapshots store the bundle ids of the
-- applications visible when the mode was last left.

ALTER TABLE settings ADD COLUMN windows_stored_by_mode INTEGER;

CREATE TABLE mode_workspace_snapshots (
    mode_id    TEXT PRIMARY KEY,
    bundle_ids TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
