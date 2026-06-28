import Foundation
import Testing
@testable import CerebralCore

// NIC-40 (PRE-MODE-5): config versioning + deterministic migrations.
// FR-CFG-05 (version + deterministic migrations, unrelated/unknown fields
// survive), FR-UPD-05 (forward, idempotent, fixture-covered, applied once).

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func fixture(_ relativePath: String) throws -> JSONValue {
    let url = repositoryRoot()
        .appendingPathComponent("packages/contracts/fixtures", isDirectory: true)
        .appendingPathComponent(relativePath)
    return try JSONValue(data: Data(contentsOf: url))
}

private func json(_ literal: String) throws -> JSONValue {
    try JSONValue(data: Data(literal.utf8))
}

// MARK: - Example migrations (production registry is empty at genesis 1.0.0)

private struct RenameAppsMigration: ConfigMigration {
    let fromVersion = "0.9.0"
    let toVersion = "1.0.0"
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue] {
        var out = document
        if let apps = out["apps"] {
            out["quickApps"] = apps
            out.removeValue(forKey: "apps")
        }
        out["schemaVersion"] = .string(toVersion)
        return out
    }
}

private struct AddFlagMigration: ConfigMigration {
    let fromVersion = "0.8.0"
    let toVersion = "0.9.0"
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue] {
        var out = document
        out["migratedFlag"] = .bool(true)
        out["schemaVersion"] = .string(toVersion)
        return out
    }
}

private struct ThrowingMigration: ConfigMigration {
    let fromVersion = "0.9.0"
    let toVersion = "1.0.0"
    struct Boom: Error {}
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue] { throw Boom() }
}

// MARK: - Deterministic upgrade + unknown-field preservation (AC1, AC2)

@Test("a supported old fixture migrates to the expected new state, preserving unknown fields")
func migratesLegacyFixtureToExpected() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [RenameAppsMigration()])
    let legacy = try fixture("migrations/config/legacy-developer-override.json")
    let expected = try fixture("migrations/config/expected-developer-override.json")

    guard case let .migrated(result, applied) = migrator.migrate(legacy) else {
        Issue.record("Expected a migrated outcome.")
        return
    }
    // Renames apps->quickApps, bumps version, and keeps id + the unknown x-user-note.
    #expect(result == expected)
    #expect(applied == [AppliedMigration(from: "0.9.0", to: "1.0.0")])
}

@Test("migration is deterministic and applies each step exactly once")
func migrationIsDeterministicAndAppliedOnce() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [RenameAppsMigration()])
    let legacy = try fixture("migrations/config/legacy-developer-override.json")

    let first = migrator.migrate(legacy)
    let second = migrator.migrate(legacy)
    #expect(first == second)
    if case let .migrated(_, applied) = first {
        #expect(applied.count == 1)
    } else {
        Issue.record("Expected a migrated outcome.")
    }
}

@Test("a multi-step chain applies migrations in version order")
func multiStepChainAppliesInOrder() throws {
    let migrator = ConfigMigrator(
        currentVersion: "1.0.0",
        migrations: [RenameAppsMigration(), AddFlagMigration()]
    )
    let document = try json(#"{"schemaVersion":"0.8.0","id":"developer","apps":["vscode"],"x-keep":"yes"}"#)

    guard case let .migrated(result, applied) = migrator.migrate(document) else {
        Issue.record("Expected a migrated outcome.")
        return
    }
    #expect(applied == [
        AppliedMigration(from: "0.8.0", to: "0.9.0"),
        AppliedMigration(from: "0.9.0", to: "1.0.0"),
    ])
    let expected = try json(#"{"schemaVersion":"1.0.0","id":"developer","quickApps":["vscode"],"migratedFlag":true,"x-keep":"yes"}"#)
    #expect(result == expected)
}

// MARK: - Idempotence (FR-UPD-05)

@Test("a document already at the current version is left unchanged")
func currentVersionIsUpToDate() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [RenameAppsMigration()])
    let current = try json(#"{"schemaVersion":"1.0.0","id":"developer","quickApps":[]}"#)
    #expect(migrator.migrate(current) == .upToDate(current))
}

// MARK: - Failure leaves the old config usable (AC3)

@Test("a throwing migration fails and returns the original document unchanged")
func failedMigrationKeepsOriginal() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [ThrowingMigration()])
    let legacy = try fixture("migrations/config/legacy-developer-override.json")

    guard case let .failed(error, original) = migrator.migrate(legacy) else {
        Issue.record("Expected a failed outcome.")
        return
    }
    #expect(error == .migrationFailed(from: "0.9.0", to: "1.0.0", reason: "Boom()"))
    #expect(original == legacy)
}

@Test("an unsupported version fails without altering the document")
func unsupportedVersionKeepsOriginal() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [RenameAppsMigration()])
    let document = try json(#"{"schemaVersion":"0.5.0","id":"developer"}"#)

    #expect(migrator.migrate(document) == .failed(.unsupportedVersion("0.5.0"), original: document))
}

@Test("a document without a version field fails closed")
func missingVersionFails() throws {
    let migrator = ConfigMigrator(currentVersion: "1.0.0", migrations: [RenameAppsMigration()])
    let document = try json(#"{"id":"developer"}"#)
    #expect(migrator.migrate(document) == .failed(.missingVersion, original: document))
}

// MARK: - Genesis production registry

@Test("the production migrator is a no-op at the current version and rejects older versions")
func productionMigratorGenesisState() throws {
    let migrator = ConfigMigrations.migrator()
    let current = try json(#"{"schemaVersion":"1.0.0","id":"developer"}"#)
    #expect(migrator.migrate(current) == .upToDate(current))

    let legacy = try json(#"{"schemaVersion":"0.9.0","id":"developer"}"#)
    #expect(migrator.migrate(legacy) == .failed(.unsupportedVersion("0.9.0"), original: legacy))
}
