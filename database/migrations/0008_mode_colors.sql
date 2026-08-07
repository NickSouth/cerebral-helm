-- Migration 0008: per-mode accent color overrides (NIC-137).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains a JSON map of
-- design-token name (e.g. executive.primary) to a #rrggbb hex value; NULL means
-- no overrides, so every mode uses its shipped palette.

ALTER TABLE settings ADD COLUMN mode_colors TEXT;
