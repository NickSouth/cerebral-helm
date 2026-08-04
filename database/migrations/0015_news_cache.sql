-- Migration 0015: the news cache (the metered-provider quota fix).
-- Human-readable mirror of the canonical embedded SQL in SchemaMigrations.swift;
-- a test keeps the two in lockstep. A single-row table holds every relevance
-- profile's last known headlines plus the last fetch-attempt time as one
-- inspectable JSON blob, so an app relaunch or a dashboard occlusion flap renders
-- from disk instead of spending a request against a small daily quota.
-- Rebuildable derived state, not user data: absent/undecodable = no cache yet.

CREATE TABLE news_cache (
    id         INTEGER PRIMARY KEY CHECK (id = 1),
    cache_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
