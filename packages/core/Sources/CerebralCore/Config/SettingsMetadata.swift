import Foundation

/// Rollback/version metadata recorded when a configuration activates (the
/// pre-SQLite stand-in for the future `settings_metadata` table: active config
/// versions and last-known-good references).
///
/// It records the version that is now active, the version of the snapshot that
/// would be restored on rollback, and any migrations applied during this
/// activation — so an operator can see what upgraded and what to fall back to.
public struct SettingsMetadata: Codable, Equatable, Sendable {
    public let activeConfigVersion: String
    public let lastKnownGoodVersion: String?
    public let appliedMigrations: [AppliedMigration]

    public init(
        activeConfigVersion: String,
        lastKnownGoodVersion: String?,
        appliedMigrations: [AppliedMigration]
    ) {
        self.activeConfigVersion = activeConfigVersion
        self.lastKnownGoodVersion = lastKnownGoodVersion
        self.appliedMigrations = appliedMigrations
    }
}
