import Foundation
import Testing

import CerebralCore
import CerebralStorage

private struct TransactionBoom: Error {}

@Test("all value types round-trip through a table")
func valueRoundTrip() throws {
    let db = try SQLiteDatabase(location: .memory)
    try db.execute("CREATE TABLE v (i INTEGER, r REAL, t TEXT, b BLOB, n TEXT);")
    try db.run(
        "INSERT INTO v (i, r, t, b, n) VALUES (?, ?, ?, ?, ?);",
        [.integer(42), .real(3.5), .text("hello"), .blob([0x01, 0x02, 0xFF]), .null]
    )

    let rows = try db.query("SELECT i, r, t, b, n FROM v;")
    #expect(rows.count == 1)
    let row = rows[0]
    #expect(row.integer("i") == 42)
    #expect(row.double("r") == 3.5)
    #expect(row.text("t") == "hello")
    #expect(row.blob("b") == [0x01, 0x02, 0xFF])
    #expect(row["n"] == .null)
}

@Test("a committed transaction persists its writes")
func transactionCommit() throws {
    let db = try SQLiteDatabase(location: .memory)
    try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);")
    try db.transaction {
        try db.run("INSERT INTO t (v) VALUES (?);", [.text("x")])
        try db.run("INSERT INTO t (v) VALUES (?);", [.text("y")])
    }
    let rows = try db.query("SELECT COUNT(*) AS c FROM t;")
    #expect(rows[0].integer("c") == 2)
}

@Test("a throwing transaction rolls back all writes")
func transactionRollback() throws {
    let db = try SQLiteDatabase(location: .memory)
    try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);")
    try db.run("INSERT INTO t (v) VALUES (?);", [.text("before")])

    #expect(throws: TransactionBoom.self) {
        try db.transaction {
            try db.run("INSERT INTO t (v) VALUES (?);", [.text("doomed")])
            throw TransactionBoom()
        }
    }

    let rows = try db.query("SELECT v FROM t;")
    #expect(rows.count == 1)
    #expect(rows[0].text("v") == "before")
}

@Test("data persists across separate connections to the same file")
func filePersistsAcrossConnections() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-storage-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("cerebral.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let writer = try SQLiteDatabase(location: .file(url))
        try writer.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL);")
        try writer.run("INSERT INTO t (name) VALUES (?);", [.text("durable")])
    }

    let reader = try SQLiteDatabase(location: .file(url))
    let rows = try reader.query("SELECT name FROM t;")
    #expect(rows.count == 1)
    #expect(rows[0].text("name") == "durable")
}

@Test("opening a missing file without create maps to cannotOpen")
func missingFileMapsToCannotOpen() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-missing-\(UUID().uuidString).sqlite")
    do {
        _ = try SQLiteDatabase(location: .file(url), create: false)
        Issue.record("expected opening a missing file to fail")
    } catch let error as StorageError {
        guard case .cannotOpen = error else {
            Issue.record("expected cannotOpen, got \(error)")
            return
        }
    } catch {
        Issue.record("expected a StorageError, got \(error)")
    }
}

@Test("invalid SQL throws a structured StorageError")
func invalidSQLThrows() throws {
    let db = try SQLiteDatabase(location: .memory)
    #expect(throws: StorageError.self) {
        try db.execute("CREATE TABLE (;")
    }
}

@Test("foreign key enforcement is enabled on every connection")
func foreignKeysEnabled() throws {
    let db = try SQLiteDatabase(location: .memory)
    let rows = try db.query("PRAGMA foreign_keys;")
    #expect(rows.first?.integer("foreign_keys") == 1)
}

@Test("last insert rowid reflects the most recent insert")
func lastInsertRowIDTracksInserts() throws {
    let db = try SQLiteDatabase(location: .memory)
    try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);")
    try db.run("INSERT INTO t (v) VALUES (?);", [.text("a")])
    #expect(db.lastInsertRowID == 1)
    try db.run("INSERT INTO t (v) VALUES (?);", [.text("b")])
    #expect(db.lastInsertRowID == 2)
}

@Test("workspace paths expose the operational database under the state root")
func operationalDatabasePathUnderStateRoot() throws {
    let paths = try WorkspacePaths.temporary(
        repositoryRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    #expect(paths.operationalDatabasePath.lastPathComponent == "cerebral.sqlite")
    #expect(paths.operationalDatabasePath.deletingLastPathComponent().lastPathComponent == "database")
    #expect(paths.operationalDatabasePath.path.hasPrefix(paths.stateRoot.path))
}
