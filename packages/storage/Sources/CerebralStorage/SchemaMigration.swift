import Foundation
import CerebralShared

/// One forward, immutable schema migration. `id` orders application (zero-padded,
/// e.g. `0001_initial`); `sql` is the statements to apply. The `checksum` over the
/// SQL is what drift detection compares against, so an already-applied migration
/// must never be edited — add a new migration instead.
public struct SchemaMigration: Equatable, Sendable {
    public let id: String
    public let sql: String

    public init(id: String, sql: String) {
        self.id = id
        self.sql = sql
    }

    /// Stable content hash of the migration SQL (vendored SHA-256).
    public var checksum: String { SHA256.hexDigest(of: sql) }
}

/// A migration row recorded in `schema_migrations`.
public struct AppliedSchemaMigration: Equatable, Sendable {
    public let id: String
    public let checksum: String
    public let appliedAt: String
}

/// A failure raised while applying schema migrations.
public enum MigrationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// An already-applied migration's recorded checksum no longer matches its
    /// current definition — the migration was edited after being applied (AC-46.2).
    case checksumMismatch(id: String, recorded: String, current: String)

    public var description: String {
        switch self {
        case let .checksumMismatch(id, recorded, current):
            return "Migration \(id) checksum drift: recorded \(recorded), current \(current)."
        }
    }
}

/// Applies the ordered set of forward, immutable schema migrations to a database,
/// recording each in `schema_migrations` with its checksum (FR-OBS-01, FR-UPD-05).
///
/// - An empty database reaches the current schema by applying every migration in
///   order (AC-46.1).
/// - Re-running is a no-op: a migration whose recorded checksum matches is skipped,
///   so application is idempotent.
/// - A migration whose recorded checksum differs from its current definition is
///   drift and fails fast without applying anything further (AC-46.2).
///
/// Each migration applies inside its own transaction together with its
/// `schema_migrations` insert, so a partial apply cannot record a migration that
/// did not fully run.
public struct SchemaMigrator: Sendable {
    public let migrations: [SchemaMigration]
    private let clock: any TimeSource

    public init(migrations: [SchemaMigration] = SchemaMigrations.all, clock: any TimeSource = SystemClock()) {
        self.migrations = migrations
        self.clock = clock
    }

    private static let registryTable = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        id TEXT PRIMARY KEY,
        checksum TEXT NOT NULL,
        applied_at TEXT NOT NULL
    );
    """

    /// Applies every not-yet-recorded migration in order. Returns the ids applied
    /// during this call (empty when already up to date).
    @discardableResult
    public func migrate(_ database: SQLiteDatabase) throws -> [String] {
        try database.execute(Self.registryTable)
        let recorded = try recordedChecksums(database)

        var appliedNow: [String] = []
        for migration in migrations {
            if let recordedChecksum = recorded[migration.id] {
                guard recordedChecksum == migration.checksum else {
                    throw MigrationError.checksumMismatch(
                        id: migration.id, recorded: recordedChecksum, current: migration.checksum
                    )
                }
                continue // already applied, unchanged
            }

            let appliedAt = StorageTimestamp.iso8601(from: clock.now())
            try database.transaction {
                try database.execute(migration.sql)
                try database.run(
                    "INSERT INTO schema_migrations (id, checksum, applied_at) VALUES (?, ?, ?);",
                    [.text(migration.id), .text(migration.checksum), .text(appliedAt)]
                )
            }
            appliedNow.append(migration.id)
        }
        return appliedNow
    }

    /// The migrations recorded as applied, ordered by id.
    public func appliedMigrations(_ database: SQLiteDatabase) throws -> [AppliedSchemaMigration] {
        try database.execute(Self.registryTable)
        let rows = try database.query("SELECT id, checksum, applied_at FROM schema_migrations ORDER BY id;")
        return rows.map { row in
            AppliedSchemaMigration(
                id: row.text("id") ?? "",
                checksum: row.text("checksum") ?? "",
                appliedAt: row.text("applied_at") ?? ""
            )
        }
    }

    private func recordedChecksums(_ database: SQLiteDatabase) throws -> [String: String] {
        let rows = try database.query("SELECT id, checksum FROM schema_migrations;")
        var result: [String: String] = [:]
        for row in rows where row.text("id") != nil {
            result[row.text("id")!] = row.text("checksum") ?? ""
        }
        return result
    }
}

/// ISO-8601 timestamp formatting for operational rows. A fresh formatter per call
/// avoids shared mutable state; migrations and (later) repository writes are
/// infrequent relative to the cost.
enum StorageTimestamp {
    static func iso8601(from date: Date) -> String {
        formatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter().date(from: string)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
