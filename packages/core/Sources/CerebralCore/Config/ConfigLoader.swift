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

    public init(workspace: WorkspacePaths) {
        self.workspace = workspace
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
        for url in overrideFiles() {
            let label = "overrides/\(url.lastPathComponent)"
            guard let data = try? Data(contentsOf: url) else {
                errors.append(unreadable(file: label))
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

        let active = ActiveConfig(
            defaults: base.defaults,
            modes: mergedModes,
            agents: base.agents,
            toolIDs: base.toolIDs
        )
        persistLastKnownGood(active)
        return .activated(active)
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
            return mode.with(quickApps: override.quickApps)
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
        try? data.write(to: workspace.activeConfigPath)
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
