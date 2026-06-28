import Foundation
import Testing

import CerebralShared
import CerebralStorage

private let expectedTables = [
    "schema_migrations", "commands", "command_events", "tool_calls",
    "confirmations", "note_metadata", "mode_sessions", "settings_metadata", "updates",
    "mode_state",
]

private let expectedIndexes = [
    "idx_commands_created_at", "idx_commands_status",
    "idx_command_events_command_id", "idx_command_events_occurred_at",
    "idx_tool_calls_command_id", "idx_tool_calls_tool_id",
    "idx_confirmations_expires_at",
    "idx_note_metadata_project", "idx_note_metadata_updated_at",
    "idx_mode_sessions_started_at", "idx_mode_sessions_mode_id",
    "idx_settings_metadata_recorded_at",
    "idx_updates_recorded_at",
]

private func tableNames(_ db: SQLiteDatabase) throws -> Set<String> {
    Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.text("name") })
}

private func indexNames(_ db: SQLiteDatabase) throws -> Set<String> {
    Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'index';").compactMap { $0.text("name") })
}

@Test("an empty database reaches the current schema (AC-46.1)")
func emptyDatabaseReachesSchema() throws {
    let db = try SQLiteDatabase(location: .memory)
    let applied = try SchemaMigrator().migrate(db)

    #expect(applied == SchemaMigrations.all.map(\.id))
    let tables = try tableNames(db)
    for table in expectedTables {
        #expect(tables.contains(table), "missing table \(table)")
    }
    let recorded = try SchemaMigrator().appliedMigrations(db)
    #expect(recorded.map(\.id) == SchemaMigrations.all.map(\.id))
    #expect(recorded.first?.checksum == SchemaMigrations.all[0].checksum)
}

@Test("re-running migrations is an idempotent no-op")
func migrationsAreIdempotent() throws {
    let db = try SQLiteDatabase(location: .memory)
    let migrator = SchemaMigrator()
    _ = try migrator.migrate(db)
    let secondRun = try migrator.migrate(db)

    #expect(secondRun.isEmpty)
    let rows = try db.query("SELECT COUNT(*) AS c FROM schema_migrations;")
    #expect(rows[0].integer("c") == Int64(SchemaMigrations.all.count))
    #expect(try tableNames(db).isSuperset(of: expectedTables))
}

@Test("a tampered applied checksum is detected as drift (AC-46.2)")
func tamperedChecksumIsDrift() throws {
    let db = try SQLiteDatabase(location: .memory)
    let migrator = SchemaMigrator()
    _ = try migrator.migrate(db)

    try db.run("UPDATE schema_migrations SET checksum = ? WHERE id = ?;", [.text("deadbeef"), .text("0001_initial")])

    do {
        _ = try migrator.migrate(db)
        Issue.record("expected checksum drift to be detected")
    } catch let error as MigrationError {
        guard case let .checksumMismatch(id, recorded, _) = error else {
            Issue.record("expected checksumMismatch, got \(error)")
            return
        }
        #expect(id == "0001_initial")
        #expect(recorded == "deadbeef")
    }
}

@Test("editing an already-applied migration is detected as drift (AC-46.2)")
func editedMigrationIsDrift() throws {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)

    let edited = SchemaMigrator(migrations: [
        SchemaMigration(id: "0001_initial", sql: "CREATE TABLE drift (id INTEGER PRIMARY KEY);"),
    ])
    #expect(throws: MigrationError.self) {
        _ = try edited.migrate(db)
    }
}

@Test("foreign keys are enforced after migration (AC-46.3)")
func foreignKeysEnforced() throws {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)

    try db.run(
        "INSERT INTO commands (id, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
        [.text("cmd_00000001"), .text("cli"), .text("received"), .text("2026-06-28T00:00:00.000Z"), .text("2026-06-28T00:00:00.000Z")]
    )

    // An event referencing a missing command violates the foreign key.
    do {
        _ = try db.run(
            "INSERT INTO command_events (id, command_id, status, occurred_at) VALUES (?, ?, ?, ?);",
            [.text("evt_00000001"), .text("cmd_missing01"), .text("received"), .text("2026-06-28T00:00:01.000Z")]
        )
        Issue.record("expected a foreign-key constraint violation")
    } catch let error as StorageError {
        guard case .constraintViolation = error else {
            Issue.record("expected constraintViolation, got \(error)")
            return
        }
    }

    // The same insert against the real command succeeds.
    let changes = try db.run(
        "INSERT INTO command_events (id, command_id, status, occurred_at) VALUES (?, ?, ?, ?);",
        [.text("evt_00000001"), .text("cmd_00000001"), .text("received"), .text("2026-06-28T00:00:01.000Z")]
    )
    #expect(changes == 1)
}

@Test("ON DELETE CASCADE removes a command's events and tool calls")
func deleteCascades() throws {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)

    try db.run(
        "INSERT INTO commands (id, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
        [.text("cmd_00000001"), .text("cli"), .text("succeeded"), .text("2026-06-28T00:00:00.000Z"), .text("2026-06-28T00:00:02.000Z")]
    )
    try db.run(
        "INSERT INTO command_events (id, command_id, status, occurred_at) VALUES (?, ?, ?, ?);",
        [.text("evt_00000001"), .text("cmd_00000001"), .text("succeeded"), .text("2026-06-28T00:00:02.000Z")]
    )
    try db.run(
        """
        INSERT INTO tool_calls (command_id, tool_id, tool_version, adapter_id, status, started_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """,
        [.text("cmd_00000001"), .text("note.search"), .text("1.0.0"), .text("mock_native"), .text("success"),
         .text("2026-06-28T00:00:01.000Z"), .text("2026-06-28T00:00:02.000Z")]
    )

    try db.run("DELETE FROM commands WHERE id = ?;", [.text("cmd_00000001")])

    #expect(try db.query("SELECT COUNT(*) AS c FROM command_events;")[0].integer("c") == 0)
    #expect(try db.query("SELECT COUNT(*) AS c FROM tool_calls;")[0].integer("c") == 0)
}

@Test("a later migration applies forward on an existing database, preserving data")
func forwardMigrationOnExistingDatabase() throws {
    let db = try SQLiteDatabase(location: .memory)

    // First release: only migration 0001 exists.
    let firstRelease = SchemaMigrator(migrations: [SchemaMigrations.all[0]])
    #expect(try firstRelease.migrate(db) == ["0001_initial"])
    try db.run(
        "INSERT INTO commands (id, source, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?);",
        [.text("cmd_keep0001"), .text("cli"), .text("succeeded"), .text("2026-06-28T00:00:00.000Z"), .text("2026-06-28T00:00:00.000Z")]
    )

    // Next release adds 0002: only the new migration runs, and prior data survives.
    let applied = try SchemaMigrator().migrate(db)
    #expect(applied == ["0002_mode_state"])
    #expect(try tableNames(db).contains("mode_state"))
    #expect(try db.query("SELECT COUNT(*) AS c FROM commands;")[0].integer("c") == 1)
}

@Test("required indexes are created (AC-46.3)")
func requiredIndexesPresent() throws {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    #expect(try indexNames(db).isSuperset(of: expectedIndexes))
}

@Test("applied_at is the injected clock's instant (deterministic)")
func appliedAtUsesInjectedClock() throws {
    let db = try SQLiteDatabase(location: .memory)
    let instant = Date(timeIntervalSince1970: 1_750_000_000)
    _ = try SchemaMigrator(clock: FixedClock(instant)).migrate(db)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let recorded = try SchemaMigrator().appliedMigrations(db)
    #expect(recorded.first?.appliedAt == formatter.string(from: instant))
}

@Test("migrations persist to a file database across connections")
func migrationsPersistToFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-migrate-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("cerebral.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let db = try SQLiteDatabase(location: .file(url))
        _ = try SchemaMigrator().migrate(db)
    }
    // A fresh connection sees the committed schema, and re-running is a no-op.
    let reopened = try SQLiteDatabase(location: .file(url))
    #expect(try tableNames(reopened).isSuperset(of: expectedTables))
    #expect(try SchemaMigrator().migrate(reopened).isEmpty)
}

@Test("each checked-in .sql mirror matches its embedded canonical migration")
func sqlMirrorsMatchEmbedded() throws {
    let migrationsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("database", isDirectory: true)
        .appendingPathComponent("migrations", isDirectory: true)

    for migration in SchemaMigrations.all {
        let sqlURL = migrationsDir.appendingPathComponent("\(migration.id).sql")
        let fileSQL = try String(contentsOf: sqlURL, encoding: .utf8)
        #expect(normalizedSchema(fileSQL) == normalizedSchema(migration.sql), "mirror drift in \(migration.id)")
    }
}

/// Reduces SQL to its executable statements: drops blank lines and full-line
/// comments and collapses whitespace, so the mirror and the embedded source can
/// carry different header comments but never a different schema.
private func normalizedSchema(_ sql: String) -> String {
    sql
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("--") }
        .joined(separator: " ")
        .split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
}
