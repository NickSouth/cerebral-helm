import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// The news cache store (the metered-provider quota fix): every profile's last known headlines and
/// the last fetch-attempt time persist in SQLite as one inspectable JSON blob, so a relaunch
/// renders from disk instead of spending a request against a ~200/day quota. Saving replaces
/// wholesale. The cache is rebuildable derived state, so a garbled row degrades to "no cache yet"
/// rather than throwing — that costs one extra request and heals on the next fetch.

private func makeStore() throws -> (SQLiteNewsCacheStore, SQLiteDatabase) {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return (SQLiteNewsCacheStore(database: db), db)
}

private let fetchedAt = Date(timeIntervalSince1970: 1_750_000_000)

private let sampleCache = NewsCacheSnapshot(
    entries: [
        "broad": NewsCacheEntry(
            headlines: [
                NewsHeadline(id: "n1", title: "Markets steady", source: "Reuters", url: "https://ex.com/a"),
                // A headline with no link — the url stays nil, never fabricated.
                NewsHeadline(id: "n2", title: "Rates held", source: "Bloomberg"),
            ],
            fetchedAt: fetchedAt
        ),
        "engineering": NewsCacheEntry(headlines: [], failure: .unavailable, fetchedAt: fetchedAt),
    ],
    lastAttemptAt: fetchedAt
)

@Test("a store with no cache loads nil — no cache yet, never an error")
func newsCacheMissingLoadsNil() throws {
    #expect(try makeStore().0.load() == nil)
}

@Test("a cache snapshot round-trips: headlines, failures, fetchedAt, lastAttemptAt")
func newsCacheRoundTrips() throws {
    let (store, _) = try makeStore()
    try store.save(sampleCache)
    #expect(try store.load() == sampleCache)
}

@Test("the newest cache replaces the previous wholesale, never merges")
func newsCacheSaveReplacesWholesale() throws {
    let (store, _) = try makeStore()
    try store.save(sampleCache)
    let newer = NewsCacheSnapshot(
        entries: ["broad": NewsCacheEntry(headlines: [], failure: .credentialsMissing, fetchedAt: fetchedAt)],
        lastAttemptAt: fetchedAt.addingTimeInterval(3600)
    )
    try store.save(newer)
    #expect(try store.load() == newer)
    // The profile that is gone from the newest cache is gone from the row, not merged forward.
    #expect(try store.load()?.entries["engineering"] == nil)
}

@Test("an unreadable cache row degrades to nil rather than throwing")
func newsCacheUndecodableRowLoadsNil() throws {
    let (store, db) = try makeStore()
    _ = try db.run(
        "INSERT INTO news_cache (id, cache_json, updated_at) VALUES (1, ?, ?);",
        [.text("{not valid json"), .text("2026-08-04T00:00:00.000Z")]
    )
    #expect(try store.load() == nil)
}

@Test("a never-fetched cache round-trips with no lastAttemptAt")
func newsCacheEmptyRoundTrips() throws {
    let (store, _) = try makeStore()
    let empty = NewsCacheSnapshot()
    try store.save(empty)
    #expect(try store.load() == empty)
    #expect(try store.load()?.lastAttemptAt == nil)
}
