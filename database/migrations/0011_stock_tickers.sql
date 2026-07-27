-- Migration 0011: the "Stocks tickers" setting (NIC-128).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. The settings singleton gains a JSON array of
-- the user's tracked stock symbols for the Executive Stocks widget; NULL means
-- never set (the shipped starter list applies), while an explicit [] is a
-- meaningful "cleared" state.

ALTER TABLE settings ADD COLUMN stock_tickers TEXT;
