-- Migration 0013: the Canvas scrape snapshot (NIC-132).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. A single-row table holds the latest scrape of
-- the School dashboard's courses/grades and upcoming deadlines as one inspectable
-- JSON blob; the newest scrape replaces it wholesale. Scraped grade data is
-- personal and stays local (ADR-006 operational state under the state root). An
-- absent row means "no scrape yet", so the widgets show their honest unavailable
-- state until the Chrome extension posts one.

CREATE TABLE canvas_snapshot (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    snapshot_json TEXT NOT NULL,
    updated_at    TEXT NOT NULL
);
