import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// The Canvas hidden-item store (NIC-132): the user's hidden course/assignment ids persist in SQLite
/// as one JSON array, replaced wholesale, and survive across scrapes.

private func makeHiddenStore() throws -> (SQLiteCanvasHiddenStore, SQLiteDatabase) {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return (SQLiteCanvasHiddenStore(database: db), db)
}

@Test("an unset hidden store returns an empty set")
func canvasHiddenEmptyByDefault() throws {
    #expect(try makeHiddenStore().0.hiddenIds() == [])
}

@Test("hidden ids round-trip and a re-save replaces the set wholesale")
func canvasHiddenRoundTrips() throws {
    let (store, _) = try makeHiddenStore()
    try store.setHiddenIds(["37331", "a1"])
    #expect(try store.hiddenIds() == ["37331", "a1"])
    try store.setHiddenIds(["a1"])
    #expect(try store.hiddenIds() == ["a1"])
}

@Test("clear() removes every hidden id")
func canvasHiddenClears() throws {
    let (store, _) = try makeHiddenStore()
    try store.setHiddenIds(["x", "y"])
    try store.clear()
    #expect(try store.hiddenIds() == [])
}
