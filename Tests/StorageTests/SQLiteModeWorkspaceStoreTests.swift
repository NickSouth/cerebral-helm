import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// "Windows Stored by Mode" (NIC-85): per-mode workspace snapshots persist in
/// SQLite as inspectable bundle-id lists; saving replaces wholesale.

private func makeStore() throws -> SQLiteModeWorkspaceStore {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return SQLiteModeWorkspaceStore(database: db)
}

@Test("a mode with no stored snapshot loads nil — nothing to restore, never an error")
func missingSnapshotLoadsNil() throws {
    #expect(try makeStore().loadSnapshot(modeID: "developer") == nil)
}

@Test("a snapshot round-trips per mode and a re-save replaces it wholesale")
func snapshotRoundTripsAndReplaces() throws {
    let store = try makeStore()
    try store.saveSnapshot(modeID: "developer", bundleIDs: ["com.microsoft.VSCode", "com.apple.Terminal"])
    try store.saveSnapshot(modeID: "school", bundleIDs: ["com.apple.Safari"])

    #expect(try store.loadSnapshot(modeID: "developer") == ["com.microsoft.VSCode", "com.apple.Terminal"])
    #expect(try store.loadSnapshot(modeID: "school") == ["com.apple.Safari"])

    // The next departure replaces, never merges — a snapshot is "the workspace
    // when this mode was last left".
    try store.saveSnapshot(modeID: "developer", bundleIDs: ["com.apple.dt.Xcode"])
    #expect(try store.loadSnapshot(modeID: "developer") == ["com.apple.dt.Xcode"])
}

@Test("an empty snapshot is stored and distinct from never-stored")
func emptySnapshotIsStored() throws {
    let store = try makeStore()
    try store.saveSnapshot(modeID: "entertainment", bundleIDs: [])
    #expect(try store.loadSnapshot(modeID: "entertainment") == [])
}
