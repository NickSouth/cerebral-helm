import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// "Windows Stored by Mode" (NIC-85): per-mode workspace snapshots persist in
/// SQLite as inspectable JSON — app references with optional window frames —
/// and saving replaces wholesale. Legacy (pre-geometry) rows still load.

private func makeStore() throws -> (SQLiteModeWorkspaceStore, SQLiteDatabase) {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return (SQLiteModeWorkspaceStore(database: db), db)
}

@Test("a mode with no stored snapshot loads nil — nothing to restore, never an error")
func missingSnapshotLoadsNil() throws {
    #expect(try makeStore().0.loadSnapshot(modeID: "developer") == nil)
}

@Test("a snapshot with frames round-trips per mode and a re-save replaces it wholesale")
func snapshotRoundTripsAndReplaces() throws {
    let (store, _) = try makeStore()
    let vscode = WorkspaceAppSnapshot(
        bundleID: "com.microsoft.VSCode",
        frame: WindowRect(x: 0, y: 25, width: 800, height: 775)
    )
    let terminal = WorkspaceAppSnapshot(bundleID: "com.apple.Terminal", frame: nil)
    try store.saveSnapshot(modeID: "developer", apps: [vscode, terminal])
    try store.saveSnapshot(modeID: "school", apps: [WorkspaceAppSnapshot(bundleID: "com.apple.Safari")])

    #expect(try store.loadSnapshot(modeID: "developer") == [vscode, terminal])
    #expect(try store.loadSnapshot(modeID: "school")?.first?.bundleID == "com.apple.Safari")

    // The next departure replaces, never merges — a snapshot is "the workspace
    // when this mode was last left".
    try store.saveSnapshot(modeID: "developer", apps: [WorkspaceAppSnapshot(bundleID: "com.apple.dt.Xcode")])
    #expect(try store.loadSnapshot(modeID: "developer") == [WorkspaceAppSnapshot(bundleID: "com.apple.dt.Xcode")])
}

@Test("a legacy pre-geometry row (plain bundle-id array) loads as frame-less snapshots")
func legacySnapshotRowStillLoads() throws {
    let (store, db) = try makeStore()
    try db.run(
        "INSERT INTO mode_workspace_snapshots (mode_id, bundle_ids, updated_at) VALUES (?, ?, ?);",
        [.text("developer"), .text(#"["com.microsoft.VSCode","com.apple.Terminal"]"#), .text("2026-07-06T00:00:00.000Z")]
    )

    let loaded = try store.loadSnapshot(modeID: "developer")
    #expect(loaded == [
        WorkspaceAppSnapshot(bundleID: "com.microsoft.VSCode", frame: nil),
        WorkspaceAppSnapshot(bundleID: "com.apple.Terminal", frame: nil),
    ])
}

@Test("an empty snapshot is stored and distinct from never-stored")
func emptySnapshotIsStored() throws {
    let (store, _) = try makeStore()
    try store.saveSnapshot(modeID: "entertainment", apps: [])
    #expect(try store.loadSnapshot(modeID: "entertainment") == [])
}
