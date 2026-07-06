import Foundation

/// Deterministic validation of a settings-patch `changes` object (FR-CFG-04, ADR-003).
///
/// Mirrors `packages/contracts/schemas/config/settings-patch.schema.json` and the
/// dashboard's `settingsPatch.ts`: only the allowlisted keys are accepted, and a key
/// that would widen risk or permission (e.g. `toolRiskOverrides`) is a hard rejection.
/// Settings can never weaken policy — that classification is deterministic and lives
/// outside configuration. This is validation only; durable persistence belongs to the
/// settings store.
public enum SettingsPatchValidator {
    private static let allowedChangeKeys: Set<String> =
        ["defaultModeId", "appearance", "hotkeys", "knowledge", "workspace", "extensions"]
    private static let allowedAppearanceKeys: Set<String> = ["density", "reducedMotion"]
    private static let densityValues: Set<String> = ["comfortable", "compact"]
    private static let modeIDPattern = "^[a-z][a-z0-9-]*$"

    /// Returns every violation; an empty array means the patch is accepted.
    public static func validate(changes: [String: Any]) -> [String] {
        var errors: [String] = []

        for key in changes.keys where !allowedChangeKeys.contains(key) {
            errors.append("Unknown setting \"\(key)\" is not permitted by the settings-patch contract.")
        }

        if let value = changes["defaultModeId"] {
            if !(value is String) || (value as? String)?.range(of: modeIDPattern, options: .regularExpression) == nil {
                errors.append("defaultModeId must be a lowercase mode id.")
            }
        }

        if let appearance = changes["appearance"] {
            if let dict = appearance as? [String: Any] {
                for key in dict.keys where !allowedAppearanceKeys.contains(key) {
                    errors.append("Unknown appearance setting \"\(key)\".")
                }
                if let density = dict["density"], !densityValues.contains(String(describing: density)) {
                    errors.append("appearance.density must be comfortable or compact.")
                }
                if let reduced = dict["reducedMotion"], !(reduced is Bool) {
                    errors.append("appearance.reducedMotion must be a boolean.")
                }
            } else {
                errors.append("appearance must be an object.")
            }
        }

        if let knowledge = changes["knowledge"] {
            if let dict = knowledge as? [String: Any] {
                if let root = dict["rootReference"], !(root is String) {
                    errors.append("knowledge.rootReference must be a string.")
                }
            } else {
                errors.append("knowledge must be an object.")
            }
        }

        if let workspace = changes["workspace"] {
            if let dict = workspace as? [String: Any] {
                let allowedWorkspaceKeys: Set<String> = ["windowsStoredByMode", "mainDisplayId"]
                for key in dict.keys where !allowedWorkspaceKeys.contains(key) {
                    errors.append("Unknown workspace setting \"\(key)\".")
                }
                if let stored = dict["windowsStoredByMode"], !(stored is Bool) {
                    errors.append("workspace.windowsStoredByMode must be a boolean.")
                }
                if let display = dict["mainDisplayId"], !(display is String) || (display as? String)?.isEmpty == true {
                    errors.append("workspace.mainDisplayId must be a non-empty string.")
                }
            } else {
                errors.append("workspace must be an object.")
            }
        }

        if let hotkeys = changes["hotkeys"] {
            if let dict = hotkeys as? [String: Any] {
                if let palette = dict["commandPalette"], !(palette is String) {
                    errors.append("hotkeys.commandPalette must be a string.")
                }
            } else {
                errors.append("hotkeys must be an object.")
            }
        }

        return errors
    }
}
