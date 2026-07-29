-- Migration 0014: the Canvas hidden-item list (NIC-132).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. A single-row table holds the JSON array of
-- course/assignment ids the user has manually hidden from the School widgets. It
-- persists across scrapes (a hidden item stays hidden after re-syncing) and is
-- kept separate from the wholesale-replaced snapshot. Absent/empty = nothing hidden.

CREATE TABLE canvas_hidden (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    ids_json   TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
