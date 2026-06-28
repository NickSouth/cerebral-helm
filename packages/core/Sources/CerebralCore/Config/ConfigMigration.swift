import Foundation

/// One forward, deterministic configuration migration (FR-CFG-05, FR-UPD-05).
///
/// A migration upgrades a document from exactly one version to the next. It
/// receives the full object and returns the full object, so any field it does not
/// explicitly transform — including unknown user extensions — is preserved. It
/// must set the version key to ``toVersion`` and must be a pure function of its
/// input (no clocks, no randomness) so a fixture migrates the same way every run.
public protocol ConfigMigration: Sendable {
    var fromVersion: String { get }
    var toVersion: String { get }
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue]
}

/// A migration step that was applied, for audit/rollback metadata.
public struct AppliedMigration: Codable, Equatable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum ConfigMigrationError: Error, Equatable, Sendable {
    /// The document is not an object or has no string version field.
    case missingVersion
    /// No registered migration leads forward from this version.
    case unsupportedVersion(String)
    /// A migration threw while transforming the document.
    case migrationFailed(from: String, to: String, reason: String)
    /// A migration did not advance the version (would loop). A safety guard.
    case versionNotAdvanced(from: String)
}

/// The result of attempting to migrate a document.
///
/// On any failure the *original, unmodified* document is returned so the caller
/// can keep the old configuration usable rather than persisting a half-migrated
/// or invalid result (AC: invalid migration leaves the old config usable).
public enum ConfigMigrationOutcome: Equatable, Sendable {
    case upToDate(JSONValue)
    case migrated(JSONValue, applied: [AppliedMigration])
    case failed(ConfigMigrationError, original: JSONValue)
}

/// Applies an ordered chain of forward migrations to bring a versioned config
/// document up to the current schema version (FR-CFG-05).
///
/// Deterministic and idempotent: a document already at the current version is
/// returned unchanged, and a supported old document reaches the expected new
/// state by applying each step exactly once (FR-UPD-05). The engine never strips
/// fields — it only routes the document through the registered migrations — so
/// unrelated and unknown user fields survive whatever the migrations preserve.
public struct ConfigMigrator: Sendable {
    public let currentVersion: String
    private let versionKey: String
    private let migrationsByFrom: [String: any ConfigMigration]

    public init(
        currentVersion: String,
        versionKey: String = "schemaVersion",
        migrations: [any ConfigMigration] = []
    ) {
        self.currentVersion = currentVersion
        self.versionKey = versionKey
        var byFrom: [String: any ConfigMigration] = [:]
        for migration in migrations { byFrom[migration.fromVersion] = migration }
        self.migrationsByFrom = byFrom
    }

    public func migrate(_ document: JSONValue) -> ConfigMigrationOutcome {
        guard
            var object = document.objectValue,
            let version = object[versionKey]?.stringValue
        else {
            return .failed(.missingVersion, original: document)
        }

        if version == currentVersion { return .upToDate(document) }

        var current = version
        var applied: [AppliedMigration] = []
        var visited: Set<String> = []

        while current != currentVersion {
            // Guard against a cycle or a migration that fails to advance.
            guard !visited.contains(current) else {
                return .failed(.versionNotAdvanced(from: current), original: document)
            }
            visited.insert(current)

            guard let migration = migrationsByFrom[current] else {
                return .failed(.unsupportedVersion(current), original: document)
            }

            do {
                object = try migration.migrate(object)
            } catch {
                return .failed(
                    .migrationFailed(from: migration.fromVersion, to: migration.toVersion, reason: "\(error)"),
                    original: document
                )
            }

            guard
                let newVersion = object[versionKey]?.stringValue,
                newVersion == migration.toVersion,
                newVersion != current
            else {
                return .failed(.versionNotAdvanced(from: current), original: document)
            }

            applied.append(AppliedMigration(from: current, to: newVersion))
            current = newVersion
        }

        return .migrated(.object(object), applied: applied)
    }
}

/// The production config migration registry.
///
/// The shipped config is genesis at ``currentVersion``, so there are no
/// migrations yet — the production migrator is a no-op until the first schema
/// bump, at which point a ``ConfigMigration`` from the old version is appended
/// here (with its supported old-state fixture). Keeping the registry explicit
/// means the version and its migration path live in one inspectable place.
public enum ConfigMigrations {
    public static let currentVersion = "1.0.0"
    public static let all: [any ConfigMigration] = []

    public static func migrator() -> ConfigMigrator {
        ConfigMigrator(currentVersion: currentVersion, migrations: all)
    }
}
