-- Migration 0010: the "Layout display" setting (NIC-142).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains the stable
-- display id layout mode opens on (and whose bottom bar shows the hotswap pill);
-- NULL or a disconnected/unknown id degrades to the main display, then the
-- system primary.

ALTER TABLE settings ADD COLUMN layout_display_id TEXT;
