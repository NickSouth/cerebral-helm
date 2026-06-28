import Foundation
import CerebralShared

/// One knowledge file recorded in a backup manifest: its path and content hash.
/// Knowledge bodies are durable on disk, so the backup records a manifest for
/// integrity verification rather than duplicating every note.
public struct KnowledgeManifestEntry: Codable, Equatable, Sendable {
    public let path: String
    public let sha256: String
}

/// What a backup contains and how to verify it (FR-UPD-04).
public struct BackupManifest: Codable, Equatable, Sendable {
    public let createdAt: String
    public let databaseChecksum: String
    public let configFiles: [String]
    public let knowledge: [KnowledgeManifestEntry]
}

public enum BackupError: Error, Equatable, Sendable {
    case sourceMissing(String)
    case verificationFailed(String)
}

/// Creates, verifies, and restores a snapshot of durable user state (FR-UPD-04,
/// FR-UPD-07).
///
/// A backup snapshots the operational SQLite database and the user configuration,
/// plus a manifest of the knowledge files. The derived search index is *not*
/// treated as truth on restore — it is rebuilt from the Markdown files afterward
/// (FR-UPD-07). The Markdown bodies remain authoritative on disk and are recorded
/// by manifest for integrity checks rather than copied.
public struct BackupService: Sendable {
    private let databasePath: URL
    private let configFiles: [URL]
    private let overridesDirectory: URL
    private let knowledgeRoot: URL

    public init(databasePath: URL, configFiles: [URL], overridesDirectory: URL, knowledgeRoot: URL) {
        self.databasePath = databasePath
        self.configFiles = configFiles
        self.overridesDirectory = overridesDirectory
        self.knowledgeRoot = knowledgeRoot
    }

    /// Snapshots state into `destination` and writes a manifest. The database must
    /// exist; configuration files and overrides are included when present.
    @discardableResult
    public func createBackup(into destination: URL, now: Date) throws -> BackupManifest {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: databasePath.path) else {
            throw BackupError.sourceMissing("operational database")
        }
        let databaseBackup = destination.appendingPathComponent("cerebral.sqlite")
        try replace(databasePath, at: databaseBackup)
        let databaseChecksum = try checksum(of: databaseBackup)

        var includedConfig: [String] = []
        for file in configFiles where fileManager.fileExists(atPath: file.path) {
            try replace(file, at: destination.appendingPathComponent(file.lastPathComponent))
            includedConfig.append(file.lastPathComponent)
        }
        if fileManager.fileExists(atPath: overridesDirectory.path) {
            try replace(overridesDirectory, at: destination.appendingPathComponent("overrides"))
            includedConfig.append("overrides")
        }

        let manifest = BackupManifest(
            createdAt: StorageTimestamp.iso8601(from: now),
            databaseChecksum: databaseChecksum,
            configFiles: includedConfig,
            knowledge: try knowledgeManifest()
        )
        try writeManifest(manifest, to: destination.appendingPathComponent("manifest.json"))
        return manifest
    }

    /// Verifies a backup is readable and intact: the manifest parses, the database
    /// checksum matches, and the backed-up database opens and exposes its migration
    /// registry. Throws ``BackupError/verificationFailed(_:)`` otherwise (AC-48.1).
    public func verify(at destination: URL) throws {
        guard let manifest = try? readManifest(destination.appendingPathComponent("manifest.json")) else {
            throw BackupError.verificationFailed("manifest is missing or unreadable")
        }
        let databaseBackup = destination.appendingPathComponent("cerebral.sqlite")
        guard FileManager.default.fileExists(atPath: databaseBackup.path) else {
            throw BackupError.verificationFailed("backup database is missing")
        }
        guard try checksum(of: databaseBackup) == manifest.databaseChecksum else {
            throw BackupError.verificationFailed("backup database checksum mismatch")
        }
        do {
            let database = try SQLiteDatabase(location: .file(databaseBackup), create: false)
            _ = try database.query("SELECT COUNT(*) AS c FROM schema_migrations;")
        } catch {
            throw BackupError.verificationFailed("backup database is not readable: \(error)")
        }
    }

    /// Restores the database and configuration from a backup into their live
    /// locations. Knowledge files are left untouched (they are the source of truth),
    /// and the caller rebuilds the derived index afterward (FR-UPD-07).
    public func restore(from destination: URL) throws {
        let fileManager = FileManager.default
        let databaseBackup = destination.appendingPathComponent("cerebral.sqlite")
        guard fileManager.fileExists(atPath: databaseBackup.path) else {
            throw BackupError.sourceMissing("backup database")
        }
        try replace(databaseBackup, at: databasePath)

        for file in configFiles {
            let backup = destination.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: backup.path) { try replace(backup, at: file) }
        }
        let overridesBackup = destination.appendingPathComponent("overrides")
        if fileManager.fileExists(atPath: overridesBackup.path) { try replace(overridesBackup, at: overridesDirectory) }
    }

    // MARK: - Helpers

    private func knowledgeManifest() throws -> [KnowledgeManifestEntry] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: knowledgeRoot.path) else { return [] }
        var entries: [KnowledgeManifestEntry] = []
        let enumerator = fileManager.enumerator(at: knowledgeRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let relative = relativePath(of: url, under: knowledgeRoot)
            entries.append(KnowledgeManifestEntry(path: relative, sha256: try checksum(of: url)))
        }
        return entries.sorted { $0.path < $1.path }
    }

    private func checksum(of url: URL) throws -> String {
        SHA256.hexDigest(of: [UInt8](try Data(contentsOf: url)))
    }

    /// Copies `source` to `target`, replacing any existing target (file or directory).
    private func replace(_ source: URL, at target: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.copyItem(at: source, to: target)
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        var relative = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
        relative = relative.replacingOccurrences(of: "\\", with: "/")
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    private func writeManifest(_ manifest: BackupManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func readManifest(_ url: URL) throws -> BackupManifest {
        try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: url))
    }
}

/// Runs migrations only after a backup succeeds (FR-UPD-04): a failed backup blocks
/// the migration and leaves the current database unchanged (AC-48.1). When no
/// migrations are pending, no backup is taken.
public enum BackupGatedMigration {
    @discardableResult
    public static func migrate(
        _ database: SQLiteDatabase,
        migrator: SchemaMigrator = SchemaMigrator(),
        backup: () throws -> Void
    ) throws -> [String] {
        guard try !migrator.pendingMigrations(database).isEmpty else { return [] }
        try backup() // create + verify; a throw here blocks the migration
        return try migrator.migrate(database)
    }
}
