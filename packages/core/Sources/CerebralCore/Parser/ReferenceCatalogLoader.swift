import Foundation

/// Loads ``CommandReferences`` from a config directory.
///
/// Reads `references/{apps,urls,hooks}.json` and the mode ids from
/// `modes/*.json`. A missing reference file degrades to an empty catalog rather
/// than failing, so partial configuration does not disable the command surface
/// (PRD §4.6).
public enum ReferenceCatalogLoader {
    private struct ReferenceCatalogFile: Decodable {
        let schemaVersion: String
        let references: [ReferenceEntry]
    }

    private struct ModeIdentity: Decodable {
        let id: String
    }

    public static func load(configDirectory: URL) throws -> CommandReferences {
        let referencesDirectory = configDirectory.appendingPathComponent("references", isDirectory: true)

        let apps = try loadCatalog(referencesDirectory.appendingPathComponent("apps.json"))
        let urls = try loadCatalog(referencesDirectory.appendingPathComponent("urls.json"))
        let hooks = try loadCatalog(referencesDirectory.appendingPathComponent("hooks.json"))
        let modeIds = try loadModeIds(configDirectory.appendingPathComponent("modes", isDirectory: true))

        return CommandReferences(apps: apps, urls: urls, hooks: hooks, modeIds: modeIds)
    }

    private static func loadCatalog(_ url: URL) throws -> [ReferenceEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ReferenceCatalogFile.self, from: data).references
    }

    private static func loadModeIds(_ directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        return try files.map { try decoder.decode(ModeIdentity.self, from: Data(contentsOf: $0)).id }
    }
}
