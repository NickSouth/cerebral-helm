-- Migration 0006: the "Main display" setting (NIC-120b).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains the stable
-- display id the main dashboard backdrop is hosted on; NULL or a
-- disconnected/unknown id degrades to the system primary display.

ALTER TABLE settings ADD COLUMN main_display_id TEXT;
