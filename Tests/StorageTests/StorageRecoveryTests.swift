import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// NIC-49 (PRE-DATA-7): storage failure states map to recovery guidance (AC-49.1),
/// read-only recovery performs no writes (AC-49.2), and nothing is silently
/// discarded or auto-repaired (AC-49.3). FR-KNW-07, FR-SHL-05.

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-recovery-\(UUID().uuidString)", isDirectory: true)
}

private func migratedFileDatabase(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let database = try SQLiteDatabase(location: .file(url))
    _ = try SchemaMigrator().migrate(database)
}

@Test("storage failures map to canonical recovery codes (AC-49.1)")
func storageFailuresMapToGuidance() {
    #expect(RecoveryDiagnostic.forStorage(.locked("x")).code == "sqlite_locked")
    #expect(RecoveryDiagnostic.forStorage(.corrupt("x")).code == "sqlite_corrupt")
    #expect(RecoveryDiagnostic.forStorage(.readOnly("x")).code == "sqlite_read_only")
    #expect(RecoveryDiagnostic.forKnowledge(.rootUnavailable).code == "knowledge_root_missing")
    #expect(RecoveryDiagnostic.forKnowledge(.rootReadOnly).code == "knowledge_root_read_only")
    // every diagnostic carries actionable guidance
    #expect(!RecoveryDiagnostic.forStorage(.corrupt("x")).guidance.isEmpty)
    #expect(!RecoveryDiagnostic.forKnowledge(.rootUnavailable).guidance.isEmpty)
}

@Test("recovery codes cover the canonical storage-failure fixtures")
func recoveryCodesCoverCanonicalFixtures() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/catalog/canonical-states.json")
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let fixtures = root["fixtures"] as! [[String: Any]]
    let canonicalCodes = Set(fixtures.compactMap { fixture -> String? in
        guard (fixture["category"] as? String) == "storage_failure" else { return nil }
        return (fixture["state"] as? [String: Any])?["errorCode"] as? String
    })

    let produced: Set<String> = [
        RecoveryDiagnostic.forKnowledge(.rootUnavailable).code,
        RecoveryDiagnostic.forKnowledge(.rootReadOnly).code,
        RecoveryDiagnostic.forStorage(.locked("x")).code,
    ]
    #expect(!canonicalCodes.isEmpty)
    #expect(canonicalCodes.isSubset(of: produced))
}

@Test("a healthy migrated database validates as ready")
func healthyDatabaseValidatesReady() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dbURL = root.appendingPathComponent("database/cerebral.sqlite")
    try migratedFileDatabase(at: dbURL)

    #expect(StartupValidation.validate(operationalDatabasePath: dbURL, knowledgeRoot: root.appendingPathComponent("knowledge")) == .ready)
}

@Test("a missing database is first-run state, not a failure")
func missingDatabaseIsReady() {
    let root = temporaryRoot()
    let dbURL = root.appendingPathComponent("database/cerebral.sqlite") // never created
    #expect(StartupValidation.validate(operationalDatabasePath: dbURL, knowledgeRoot: root.appendingPathComponent("knowledge")) == .ready)
}

@Test("a corrupt database is reported for recovery and never repaired or discarded (AC-49.2, AC-49.3)")
func corruptDatabaseEntersRecoveryWithoutMutation() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dbURL = root.appendingPathComponent("database/cerebral.sqlite")
    try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let garbage = Data("this is not a sqlite database".utf8)
    try garbage.write(to: dbURL)

    let check = StartupValidation.validate(operationalDatabasePath: dbURL, knowledgeRoot: root.appendingPathComponent("knowledge"))
    guard case let .recovery(diagnostics) = check else {
        Issue.record("expected recovery, got \(check)")
        return
    }
    #expect(diagnostics.contains { $0.code == "sqlite_corrupt" })
    // The corrupt file is left exactly as-is: not repaired, not deleted (AC-49.2/49.3).
    #expect(try Data(contentsOf: dbURL) == garbage)
}

@Test("applied-migration drift enters recovery (FR-SHL-05)")
func migrationDriftEntersRecovery() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dbURL = root.appendingPathComponent("database/cerebral.sqlite")
    try migratedFileDatabase(at: dbURL)
    // Tamper a recorded checksum to simulate a migration that changed after applying.
    do {
        let database = try SQLiteDatabase(location: .file(dbURL))
        try database.run("UPDATE schema_migrations SET checksum = ? WHERE id = ?;", [.text("deadbeef"), .text("0001_initial")])
    }

    let check = StartupValidation.validate(operationalDatabasePath: dbURL, knowledgeRoot: root.appendingPathComponent("knowledge"))
    guard case let .recovery(diagnostics) = check else {
        Issue.record("expected recovery, got \(check)")
        return
    }
    #expect(diagnostics.contains { $0.code == "sqlite_migration_drift" })
}

@Test("a locked database surfaces a structured locked error mapped to recovery (AC-49.1)")
func lockedDatabaseIsStructured() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let dbURL = root.appendingPathComponent("database/cerebral.sqlite")
    try migratedFileDatabase(at: dbURL)

    let writer = try SQLiteDatabase(location: .file(dbURL))
    try writer.execute("BEGIN IMMEDIATE;") // hold the write lock
    defer { try? writer.execute("ROLLBACK;") }

    let other = try SQLiteDatabase(location: .file(dbURL), busyTimeoutMs: 0)
    do {
        try other.run(
            "INSERT INTO commands (id, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
            [.text("cmd_00000001"), .text("cli"), .text("received"), .text("2026-06-28T00:00:00.000Z"), .text("2026-06-28T00:00:00.000Z")]
        )
        Issue.record("expected a locked error")
    } catch let error as StorageError {
        guard case .locked = error else {
            Issue.record("expected locked, got \(error)")
            return
        }
        #expect(RecoveryDiagnostic.forStorage(error).code == "sqlite_locked")
    }
}
