import Foundation
import CerebralContracts

/// Authored per-mode window layouts (NIC-142), keyed by mode id.
///
/// Decodes `modes/*.json` under a config directory and returns each mode's
/// `layout` when present. A mode that fails to decode is skipped rather than
/// aborting the catalog — modes are validated in full by ``ConfigValidator``;
/// here a broken mode must not take down layout resolution.
///
/// This reads the *shipped* mode configs. Override-merged layouts (a user's
/// authored layout via the config-override write path) arrive with that write
/// path; consumers that must respect overrides should load through
/// ``ConfigLoader`` once the override side is wired.
public extension Layout {
    /// Decodes an opaque `[String: JSONAny]` override layout (NIC-142) into the
    /// typed `Layout`. The override schema carries the layout opaquely so the
    /// generated override type stays flat; the named layout types are defined once
    /// on the mode config, and this is where the two meet. Returns `nil` when the
    /// object does not match the layout schema.
    static func from(raw: [String: JSONAny]) -> Layout? {
        guard let data = try? JSONEncoder().encode(raw) else { return nil }
        return try? JSONDecoder().decode(Layout.self, from: data)
    }
}

public enum ModeLayoutCatalog {
    public static func load(configDirectory: URL) -> [String: Layout] {
        let directory = configDirectory.appendingPathComponent("modes", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }

        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        var layouts: [String: Layout] = [:]
        for file in files {
            guard
                let data = try? Data(contentsOf: file),
                let mode = try? decoder.decode(CerebralHelmModeConfig.self, from: data),
                let layout = mode.layout
            else { continue }
            layouts[mode.id] = layout
        }
        return layouts
    }
}
