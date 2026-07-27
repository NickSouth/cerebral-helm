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
        ["defaultModeId", "confirmAllActions", "appearance", "hotkeys", "knowledge", "workspace", "modeColors", "stocks", "extensions"]
    private static let allowedAppearanceKeys: Set<String> = ["density", "reducedMotion", "assistantName"]
    private static let assistantNameMaxLength = 40
    private static let densityValues: Set<String> = ["comfortable", "compact"]
    private static let modeIDPattern = "^[a-z][a-z0-9-]*$"
    private static let modeColorKeyPattern =
        "^(executive|developer|school|entertainment)\\.(primary|secondary)$"
    private static let hexColorPattern = "^#[0-9a-fA-F]{6}$"
    private static let tickerSymbolPattern = "^[A-Za-z][A-Za-z0-9.-]{0,9}$"
    private static let tickersMaxCount = 20

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

        if let confirmAll = changes["confirmAllActions"], !(confirmAll is Bool) {
            errors.append("confirmAllActions must be a boolean.")
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
                if let name = dict["assistantName"] {
                    if let string = name as? String {
                        if string.isEmpty || string.count > assistantNameMaxLength {
                            errors.append(
                                "appearance.assistantName must be 1–\(assistantNameMaxLength) characters."
                            )
                        }
                    } else {
                        errors.append("appearance.assistantName must be a string.")
                    }
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
                let allowedWorkspaceKeys: Set<String> = [
                    "windowsStoredByMode", "mainDisplayId", "layoutDisplayId"
                ]
                for key in dict.keys where !allowedWorkspaceKeys.contains(key) {
                    errors.append("Unknown workspace setting \"\(key)\".")
                }
                if let stored = dict["windowsStoredByMode"], !(stored is Bool) {
                    errors.append("workspace.windowsStoredByMode must be a boolean.")
                }
                if let display = dict["mainDisplayId"], !(display is String) || (display as? String)?.isEmpty == true {
                    errors.append("workspace.mainDisplayId must be a non-empty string.")
                }
                if let display = dict["layoutDisplayId"], !(display is String) || (display as? String)?.isEmpty == true {
                    errors.append("workspace.layoutDisplayId must be a non-empty string.")
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

        if let modeColors = changes["modeColors"] {
            if let dict = modeColors as? [String: Any] {
                for (key, value) in dict {
                    if key.range(of: modeColorKeyPattern, options: .regularExpression) == nil {
                        errors.append("modeColors key \"\(key)\" is not a known mode accent token.")
                    }
                    if let hex = value as? String {
                        if hex.range(of: hexColorPattern, options: .regularExpression) == nil {
                            errors.append("modeColors.\(key) must be a #rrggbb hex color.")
                        }
                    } else {
                        errors.append("modeColors.\(key) must be a string.")
                    }
                }
            } else {
                errors.append("modeColors must be an object.")
            }
        }

        if let stocks = changes["stocks"] {
            if let dict = stocks as? [String: Any] {
                for key in dict.keys where key != "tickers" {
                    errors.append("Unknown stocks setting \"\(key)\".")
                }
                if let tickers = dict["tickers"] {
                    if let list = tickers as? [Any] {
                        if list.count > tickersMaxCount {
                            errors.append("stocks.tickers may list at most \(tickersMaxCount) symbols.")
                        }
                        for symbol in list {
                            guard let string = symbol as? String else {
                                errors.append("stocks.tickers entries must be strings.")
                                continue
                            }
                            if string.range(of: tickerSymbolPattern, options: .regularExpression) == nil {
                                errors.append("stocks.tickers entry \"\(string)\" is not a valid ticker symbol.")
                            }
                        }
                    } else {
                        errors.append("stocks.tickers must be an array.")
                    }
                }
            } else {
                errors.append("stocks must be an object.")
            }
        }

        return errors
    }
}
