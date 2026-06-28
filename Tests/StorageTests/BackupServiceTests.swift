import Foundation
import Testing

import CerebralStorage

/// NIC-48 (PRE-DATA-6): backup, verify, and restore of durable state (FR-UPD-04).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private struct BackupBoom: Error {}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-backup-\(UUID().uuidString)", isDirectory: true)
}

private func service(in root: URL) -> (service: BackupService, db: URL, config: URL, knowledge: URL) {
    let db = root.appendingPathComponent("database/cerebral.sqlite")
    let config = root.appendingPathComponent("active-config.json")
    let knowledge = root.appendingPathComponent("knowledge", isDirectory: true)
    return (
        BackupService(
            databasePath: db,
            configFiles: [config],
            overridesDirectory: root.appendingPathComponent("overrides", isDirectory: true),
            knowledgeRoot: knowledge
        ),
        db, config, knowledge
    )
}

private func seedMigratedDatabase(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let db = try SQLiteDatabase(location: .file(url))
    _ = try SchemaMigrator().migrate(db)
}

@Test("a failed backup blocks the migration and leaves the database unchanged (AC-48.1)")
func failedBackupBlocksMigration() throws {
    let database = try SQLiteDatabase(location: .memory)

    do {
        _ = try BackupGatedMigration.migrate(database) { throw BackupBoom() }
        Issue.record("expected the backup failure to block migration")
    } catch is BackupBoom {}

    var tables = Set(try database.query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.text("name") })
    #expect(!tables.contains("commands")) // migration was blocked

    // A successful backup lets the migration proceed.
    var backedUp = false
    _ = try BackupGatedMigration.migrate(database) { backedUp = true }
    #expect(backedUp)
    tables = Set(try database.query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.text("name") })
    #expect(tables.contains("commands"))

    // With nothing pending, no backup is taken.
    var secondBackup = false
    _ = try BackupGatedMigration.migrate(database) { secondBackup = true }
    #expect(!secondBackup)
}

@Test("a backup is created, verified, and restored (AC-48.2)")
func backupRestoreRoundTrips() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (backup, dbURL, configURL, knowledgeURL) = service(in: root)

    try seedMigratedDatabase(at: dbURL)
    do {
        let db = try SQLiteDatabase(location: .file(dbURL))
        try db.run(
            "INSERT INTO commands (id, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
            [.text("cmd_keep0001"), .text("cli"), .text("succeeded"), .text("2026-06-28T00:00:00.000Z"), .text("2026-06-28T00:00:00.000Z")]
        )
    }
    try Data("{\"version\":1}".utf8).write(to: configURL)
    try FileManager.default.createDirectory(at: knowledgeURL.appendingPathComponent("inbox"), withIntermediateDirectories: true)
    try Data("# note".utf8).write(to: knowledgeURL.appendingPathComponent("inbox/x.md"))

    let destination = root.appendingPathComponent("backups/snapshot", isDirectory: true)
    let manifest = try backup.createBackup(into: destination, now: t0)
    try backup.verify(at: destination)
    #expect(manifest.knowledge.count == 1)
    #expect(manifest.configFiles.contains("active-config.json"))

    // Mutate the live state, then restore it from the backup.
    do {
        let db = try SQLiteDatabase(location: .file(dbURL))
        try db.run("DELETE FROM commands;")
    }
    try Data("{\"version\":999}".utf8).write(to: configURL)

    try backup.restore(from: destination)

    let restored = try SQLiteDatabase(location: .file(dbURL))
    #expect(try restored.query("SELECT COUNT(*) AS c FROM commands;")[0].integer("c") == 1)
    #expect(try String(contentsOf: configURL, encoding: .utf8) == "{\"version\":1}")
}

@Test("verification fails when the backup database is corrupted")
func verifyDetectsCorruption() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let (backup, dbURL, _, _) = service(in: root)
    try seedMigratedDatabase(at: dbURL)

    let destination = root.appendingPathComponent("backups/snapshot", isDirectory: true)
    _ = try backup.createBackup(into: destination, now: t0)
    try backup.verify(at: destination)

    // Tamper with the backed-up database; verification must reject it.
    try Data("not a database".utf8).write(to: destination.appendingPathComponent("cerebral.sqlite"))
    #expect(throws: BackupError.self) { try backup.verify(at: destination) }
}
