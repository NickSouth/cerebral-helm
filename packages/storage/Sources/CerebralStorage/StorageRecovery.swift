import Foundation
import CerebralCore

public extension RecoveryDiagnostic {
    /// Maps an operational-database failure to recovery guidance (AC-49.1).
    static func forStorage(_ error: StorageError) -> RecoveryDiagnostic {
        switch error {
        case .locked:
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_locked",
                summary: "The operational database is locked by another writer.",
                guidance: "Close other CerebralHelm processes and retry."
            )
        case .readOnly:
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_read_only",
                summary: "The operational database location is read-only.",
                guidance: "Grant write access to the database directory, then restart."
            )
        case .corrupt:
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_corrupt",
                summary: "The operational database is corrupt or not a database.",
                guidance: "Restore from a verified backup. The database is left untouched and will not be auto-repaired."
            )
        case .cannotOpen:
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_unavailable",
                summary: "The operational database could not be opened.",
                guidance: "Check the database path and permissions, then restart."
            )
        case let .constraintViolation(message):
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_constraint",
                summary: message,
                guidance: "This is a defect; report it with the operation that failed."
            )
        case let .message(message):
            return RecoveryDiagnostic(
                store: "operational_sqlite",
                code: "sqlite_error",
                summary: message,
                guidance: "Retry; if it persists, restore from a verified backup."
            )
        }
    }
}

/// Read-only startup pre-flight (FR-SHL-05).
///
/// Validates the operational database (it opens, is a real database, and its
/// migration history has not drifted) and the knowledge root (if it exists, it is
/// writable). On any failure it returns ``StartupCheck/recovery(_:)`` with
/// diagnostics and the caller stays read-only (AC-49.2). The check itself never
/// writes: a missing database or knowledge root is normal first-run state, and a
/// corrupt database is reported, never deleted or repaired (AC-49.3).
public enum StartupValidation {
    public static func validate(
        operationalDatabasePath: URL,
        knowledgeRoot: URL,
        migrator: SchemaMigrator = SchemaMigrator()
    ) -> StartupCheck {
        var diagnostics: [RecoveryDiagnostic] = []
        let fileManager = FileManager.default

        // Operational database: only validate an existing file. A missing database is
        // first-run state that the runtime creates and migrates separately.
        if fileManager.fileExists(atPath: operationalDatabasePath.path) {
            do {
                let database = try SQLiteDatabase(location: .file(operationalDatabasePath), create: false)
                _ = try database.query("PRAGMA integrity_check;") // forces a read; garbage → corrupt
                let drifted = try migrator.driftedMigrationIDs(database)
                if !drifted.isEmpty {
                    diagnostics.append(RecoveryDiagnostic(
                        store: "operational_sqlite",
                        code: "sqlite_migration_drift",
                        summary: "Applied migrations no longer match this build: \(drifted.joined(separator: ", ")).",
                        guidance: "Use a matching build or restore from a verified backup. Migrations are not re-applied automatically."
                    ))
                }
            } catch let error as StorageError {
                diagnostics.append(.forStorage(error))
            } catch {
                diagnostics.append(.forStorage(.message(error.localizedDescription)))
            }
        }

        // Knowledge root: an existing-but-read-only root is a failure; a missing root
        // is first-run state (capture creates it).
        if fileManager.fileExists(atPath: knowledgeRoot.path),
           !fileManager.isWritableFile(atPath: knowledgeRoot.path) {
            diagnostics.append(.forKnowledge(.rootReadOnly))
        }

        return diagnostics.isEmpty ? .ready : .recovery(diagnostics)
    }
}
