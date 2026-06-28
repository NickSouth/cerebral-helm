import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// NIC-45 (PRE-DATA-3): the SQLite note search index (FR-KNW-04/06, NFR-09).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func migratedDatabase() throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(database)
    return database
}

@Test("the SQLite search index matches title, body, and path case-insensitively")
func searchIndexMatches() throws {
    let index = SQLiteNoteSearchIndex(database: try migratedDatabase())
    try index.upsert(NoteSearchIndexEntry(
        noteID: "a", path: "inbox/a.md", title: "Ship the Helm", body: "rivet the HULL",
        sensitivity: "private", updated: t0, reviewAfter: nil
    ))
    try index.upsert(NoteSearchIndexEntry(
        noteID: "b", path: "projects/x/b.md", title: "Other", body: "sail away",
        sensitivity: nil, updated: nil, reviewAfter: nil
    ))

    #expect(try index.matches(query: "hull").map(\.noteID) == ["a"])        // body, case-insensitive
    #expect(try index.matches(query: "HELM").map(\.noteID) == ["a"])        // title, case-insensitive
    #expect(try index.matches(query: "projects/x").map(\.noteID) == ["b"])  // path
    #expect(try index.matches(query: "").map(\.noteID) == ["a", "b"])       // empty → all, in path order
}

@Test("upsert replaces an indexed note and deleteAll clears the index")
func searchIndexUpsertAndClear() throws {
    let index = SQLiteNoteSearchIndex(database: try migratedDatabase())
    try index.upsert(NoteSearchIndexEntry(noteID: "a", path: "inbox/a.md", title: "t", body: "old text", sensitivity: nil, updated: nil, reviewAfter: nil))
    try index.upsert(NoteSearchIndexEntry(noteID: "a", path: "archive/a.md", title: "t", body: "new text", sensitivity: nil, updated: nil, reviewAfter: nil))

    #expect(try index.matches(query: "old").isEmpty)
    #expect(try index.matches(query: "new").map(\.path) == ["archive/a.md"])

    try index.deleteAll()
    #expect(try index.matches(query: "").isEmpty)
}

@Test("an indexed entry round-trips its fields")
func searchIndexRoundTrips() throws {
    let index = SQLiteNoteSearchIndex(database: try migratedDatabase())
    let entry = NoteSearchIndexEntry(
        noteID: "a", path: "inbox/a.md", title: "Title", body: "body text",
        sensitivity: "private", updated: t0, reviewAfter: t0.addingTimeInterval(3600)
    )
    try index.upsert(entry)
    #expect(try index.matches(query: "body").first == entry)
}
