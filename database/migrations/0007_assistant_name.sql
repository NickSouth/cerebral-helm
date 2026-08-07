-- Migration 0007: the "Assistant Name" setting (NIC-137).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains the assistant's
-- display name shown across the dashboard; NULL means the default identity
-- (`Heimlich`) applies.

ALTER TABLE settings ADD COLUMN appearance_assistant_name TEXT;
