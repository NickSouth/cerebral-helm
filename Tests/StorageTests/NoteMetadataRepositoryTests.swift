import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// NIC-44 (PRE-DATA-2): the SQLite note-metadata store backing the durable
/// knowledge service (FR-OBS-01 `note_metadata`).

private let created = Date(timeIntervalSince1970: 1_700_000_000)

@Test("the SQLite note-metadata store upserts and reads back entries")
func noteMetadataRoundTrips() throws {
    let database = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(database)
    let store = SQLiteNoteMetadataStore(database: database)

    let entry = NoteMetadataEntry(
        noteID: "ship-the-helm", path: "projects/ch/ship-the-helm.md", title: "Ship the Helm",
        kind: "project-note", project: "ch", sensitivity: "private", cloudPolicy: "deny",
        status: "active", created: created, updated: created, reviewAfter: nil
    )
    try store.upsert(entry)

    #expect(try store.get(noteID: "ship-the-helm") == entry)
    #expect(try store.get(noteID: "missing") == nil)
}

@Test("upsert replaces a note's row rather than duplicating it")
func noteMetadataUpsertReplaces() throws {
    let database = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(database)
    let store = SQLiteNoteMetadataStore(database: database)

    let base = NoteMetadataEntry(
        noteID: "ship-the-helm", path: "inbox/ship-the-helm.md", title: "Ship the Helm",
        kind: "note", project: nil, sensitivity: "private", cloudPolicy: "deny",
        status: "active", created: created, updated: created, reviewAfter: nil
    )
    try store.upsert(base)
    let archived = NoteMetadataEntry(
        noteID: "ship-the-helm", path: "archive/ship-the-helm.md", title: "Ship the Helm",
        kind: "note", project: nil, sensitivity: "private", cloudPolicy: "deny",
        status: "archived", created: created, updated: created, reviewAfter: nil
    )
    try store.upsert(archived)

    #expect(try store.all().count == 1)
    #expect(try store.get(noteID: "ship-the-helm")?.status == "archived")
    #expect(try store.get(noteID: "ship-the-helm")?.path == "archive/ship-the-helm.md")
}
