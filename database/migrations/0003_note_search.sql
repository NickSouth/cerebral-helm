-- Operational schema 0003 (PRE-DATA-3 / FR-KNW-04, FR-KNW-06, NFR-09):
-- the rebuildable note search index.
--
-- Human-readable mirror; the canonical source is `SchemaMigrations.noteSearchSQL`
-- in the CerebralStorage package (a test keeps them identical).
--
-- A disposable derived projection of each note's searchable text. The Markdown
-- file remains the source of truth, so this table can be dropped and rebuilt from
-- disk without losing anything.

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
