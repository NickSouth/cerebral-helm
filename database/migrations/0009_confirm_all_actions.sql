-- Migration 0009: the "Ask before all actions" tightening (NIC-137).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains a flag that, when
-- set, raises every non-read-only action to require confirmation; NULL/0 means
-- descriptor policy governs.

ALTER TABLE settings ADD COLUMN confirm_all_actions INTEGER;
