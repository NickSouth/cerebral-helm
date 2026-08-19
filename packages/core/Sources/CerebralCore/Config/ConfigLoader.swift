import Foundation
import CerebralContracts

/// The outcome of a configuration load.
public enum ConfigActivation {
    /// A valid candidate became the active configuration (and the new last-known-good snapshot).
    case activated(ActiveConfig)
    /// The candidate was invalid; the last-known-good config (if any) stays active.
    case rejected(errors: [CerebralHelmConfigValidationError], lastKnownGood: ActiveConfig?)
}

/// Loads the layered configuration and activates only valid candidates.
///
/// Precedence (PRD §10.3): immutable defaults (shipped `config/`) → machine
/// capability overrides (a reserved layer; no pre-Mac source yet) → user
/// overrides (per-mode ``CerebralHelmModeOverride`` files under the environment
/// state root) → session overrides. Every layer and the merged result run
/// through ``ConfigValidator`` — including its unknown-key rejection, so an
/// override can never smuggle in a risk-weakening field.
///
/// An invalid candidate never replaces the active config: the last-known-good
/// snapshot persisted under the state root stays in force (FR-CFG-02). User
/// overrides are stored separately from defaults, so a shipped default change
/// cannot overwrite them (FR-CFG-01).
public struct ConfigLoader {
    private let workspace: WorkspacePaths
    private let migrator: ConfigMigrator

    public init(workspace: WorkspacePaths, migrator: ConfigMigrator = ConfigMigrations.migrator()) {
        self.workspace = workspace
        self.migrator = migrator
    }

    /// Builds and (if valid) activates the layered configuration, persisting it as
    /// the new last-known-good snapshot. `sessionOverrides` are applied last and
    /// win over user overrides for the same mode id.
    public func load(sessionOverrides: [CerebralHelmModeOverride] = []) -> ConfigActivation {
        // Layer: immutable shipped defaults.
        let base: ValidatedConfig
        switch ConfigValidator.validate(configDirectory: workspace.configDirectory) {
        case let .invalid(errors):
            return .rejected(errors: errors, lastKnownGood: lastKnownGood())
        case let .valid(validated):
            base = validated
        }

        // Layer: user overrides (per-mode files under the state root).
        var errors: [CerebralHelmConfigValidationError] = []
        var userOverrides: [CerebralHelmModeOverride] = []
        var appliedMigrations: [AppliedMigration] = []
        for url in overrideFiles() {
            let label = "overrides/\(url.lastPathComponent)"
            guard let rawData = try? Data(contentsOf: url) else {
                errors.append(unreadable(file: label))
                continue
            }
            // Upgrade an older supported override to the current schema before
            // validation (FR-CFG-05). A failed migration is an invalid candidate,
            // so the last-known-good config stays active (FR-CFG-02).
            let data: Data
            switch migrateOverride(rawData, file: label) {
            case let .ready(migrated, applied):
                data = migrated
                appliedMigrations += applied
            case let .invalid(error):
                errors.append(error)
                continue
            }
            let documentErrors = ConfigValidator.overrideDocumentErrors(file: label, data: data)
            errors += documentErrors
            if documentErrors.isEmpty, let override = try? CerebralHelmModeOverride(data: data) {
                userOverrides.append(override)
            }
        }
        if !errors.isEmpty {
            return .rejected(errors: errors, lastKnownGood: lastKnownGood())
        }

        // Merge user then session overrides; the merged result must still be valid.
        let mergedModes = Self.applyOverrides(base.modes, userOverrides + sessionOverrides)
        for mode in mergedModes {
            guard let data = try? mode.jsonData() else { continue }
            errors += ConfigValidator.modeDocumentErrors(file: "modes/\(mode.id).json", data: data)
        }
        if !errors.isEmpty {
            return .rejected(errors: errors, lastKnownGood: lastKnownGood())
        }

        // Capture the version we would roll back to before overwriting the snapshot.
        let rollbackVersion = lastKnownGood()?.defaults.schemaVersion

        let active = ActiveConfig(
            defaults: base.defaults,
            modes: mergedModes,
            agents: base.agents,
            toolIDs: base.toolIDs,
            modelProfiles: base.modelProfiles
        )
        persistLastKnownGood(active)
        persistSettingsMetadata(SettingsMetadata(
            activeConfigVersion: base.defaults.schemaVersion,
            lastKnownGoodVersion: rollbackVersion,
            appliedMigrations: appliedMigrations
        ))
        return .activated(active)
    }

    /// The result of migrating one override document to the current schema.
    private enum OverrideMigrationResult {
        case ready(Data, [AppliedMigration])
        case invalid(CerebralHelmConfigValidationError)
    }

    private func migrateOverride(_ rawData: Data, file: String) -> OverrideMigrationResult {
        guard let value = try? JSONValue(data: rawData) else {
            return .invalid(unreadable(file: file))
        }
        switch migrator.migrate(value) {
        case .upToDate:
            return .ready(rawData, [])
        case let .migrated(migrated, applied):
            guard let data = try? migrated.serialized() else {
                return .invalid(migrationError(file: file, message: "Migrated override could not be serialized."))
            }
            return .ready(data, applied)
        case let .failed(error, _):
            return .invalid(migrationError(file: file, message: migrationMessage(error)))
        }
    }

    private func migrationMessage(_ error: ConfigMigrationError) -> String {
        switch error {
        case .missingVersion:
            return "Override is missing a schemaVersion."
        case let .unsupportedVersion(version):
            return "Override schema version \(version) has no supported migration path."
        case let .migrationFailed(from, to, reason):
            return "Migration \(from) to \(to) failed: \(reason)."
        case let .versionNotAdvanced(from):
            return "Migration from \(from) did not advance the schema version."
        }
    }

    private func migrationError(file: String, message: String) -> CerebralHelmConfigValidationError {
        CerebralHelmConfigValidationError(
            expected: "a supported config version",
            field: "/schemaVersion",
            file: file,
            message: message,
            remediation: "Update the file to a supported version, or restore the previous version.",
            schemaVersion: ConfigValidator.schemaVersion
        )
    }

    private func persistSettingsMetadata(_ metadata: SettingsMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? FileManager.default.createDirectory(at: workspace.stateRoot, withIntermediateDirectories: true)
        // `.atomic` writes a temp file then replaces it. Without it, a crash partway
        // through leaves truncated rollback metadata, which `SettingsMetadata`
        // decoding then discards silently (NFR-06, NIC-103).
        try? data.write(to: workspace.settingsMetadataPath, options: .atomic)
    }

    /// Applies per-mode overrides onto modes, matched by id; later overrides win
    /// (so session overrides take precedence over user overrides). A mode with no
    /// override is returned unchanged. Pure and deterministic.
    public static func applyOverrides(
        _ modes: [CerebralHelmModeConfig],
        _ overrides: [CerebralHelmModeOverride]
    ) -> [CerebralHelmModeConfig] {
        var overrideByID: [String: CerebralHelmModeOverride] = [:]
        for override in overrides {
            overrideByID[override.id] = override
        }
        return modes.map { mode in
            guard let override = overrideByID[mode.id] else { return mode }
            // `with(quickApps:)` keeps the default when the override omits the field.
            var merged = mode.with(quickApps: override.quickApps)
            // A layout override (NIC-142) replaces the shipped layout wholesale. It
            // is carried opaquely, so decode it into the typed `Layout` here; a
            // malformed one was already rejected upstream by the override validator.
            if let rawLayout = override.layout, let layout = Layout.from(raw: rawLayout) {
                merged = merged.with(layout: layout)
            }
            return merged
        }
    }

    /// Reads the persisted last-known-good snapshot, or nil if none exists yet.
    public func lastKnownGood() -> ActiveConfig? {
        guard let data = try? Data(contentsOf: workspace.activeConfigPath) else { return nil }
        return try? JSONDecoder().decode(ActiveConfig.self, from: data)
    }

    private func persistLastKnownGood(_ active: ActiveConfig) {
        guard let data = try? JSONEncoder().encode(active) else { return }
        try? FileManager.default.createDirectory(
            at: workspace.stateRoot, withIntermediateDirectories: true
        )
        // `.atomic` writes a temp file then replaces it. This file is the
        // last-known-good snapshot the rollback path depends on, and `lastKnownGood()`
        // decodes it with `try?` — so a crash partway through this write would not
        // brick launch, it would silently delete the recovery point (NFR-06, NIC-103).
        try? data.write(to: workspace.activeConfigPath, options: .atomic)
    }

    private func overrideFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: workspace.overridesDirectory.path) else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: workspace.overridesDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func unreadable(file: String) -> CerebralHelmConfigValidationError {
        CerebralHelmConfigValidationError(
            expected: "a readable override file",
            field: "/",
            file: file,
            message: "Override file is unreadable.",
            remediation: "Ensure the file exists and is valid UTF-8 JSON.",
            schemaVersion: ConfigValidator.schemaVersion
        )
    }
}
