-- Operational schema 0002 (PRE-DATA-5 / FR-MOD-05): active mode and context.
--
-- Human-readable mirror; the canonical source is `SchemaMigrations.modeStateSQL`
-- in the CerebralStorage package (a test keeps them identical). This is the first
-- forward migration applied on top of an existing database.
--
-- Active mode and context are independent columns of a single row, so either can
-- change or fall back without disturbing the other.

CREATE TABLE mode_state (
    id                   INTEGER PRIMARY KEY CHECK (id = 1),
    active_mode_id       TEXT,
    active_context_id    TEXT,
    active_context_label TEXT,
    updated_at           TEXT NOT NULL
);
