-- Migration 0012: the calendar→mode mapping setting (NIC-126).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains a JSON object
-- mapping each of the user's calendars (by identifier) to a mode, driving the
-- Today panel's per-mode relevance filtering. NULL/absent means no mappings, so
-- every calendar's events fall to the default mode (Executive) at the resolver.

ALTER TABLE settings ADD COLUMN calendar_mode_map TEXT;
