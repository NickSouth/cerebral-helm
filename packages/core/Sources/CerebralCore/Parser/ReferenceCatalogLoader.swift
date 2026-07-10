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

    /// `stateRoot`, when given, additionally merges the user's minted app
    /// (``UserAppReferences``, NIC-119) and URL (``UserURLReferences``, NIC-146)
    /// references: shipped entries win on both id and target, so minting can never
    /// shadow or redefine a shipped reference. Hooks have no user layer — those
    /// stay curated config.
    public static func load(configDirectory: URL, stateRoot: URL? = nil) throws -> CommandReferences {
        let referencesDirectory = configDirectory.appendingPathComponent("references", isDirectory: true)

        var apps = try loadCatalog(referencesDirectory.appendingPathComponent("apps.json"))
        var urls = try loadCatalog(referencesDirectory.appendingPathComponent("urls.json"))
        if let stateRoot {
            apps += mergeableUserReferences(UserAppReferences.load(stateRoot: stateRoot), shipped: apps)
            urls += mergeableUserReferences(UserURLReferences.load(stateRoot: stateRoot), shipped: urls)
        }
        let hooks = try loadCatalog(referencesDirectory.appendingPathComponent("hooks.json"))
        let modeIds = try loadModeIds(configDirectory.appendingPathComponent("modes", isDirectory: true))
        let workflowIds = Array((try WorkflowCatalogLoader.load(configDirectory: configDirectory)).keys)

        return CommandReferences(apps: apps, urls: urls, hooks: hooks, modeIds: modeIds, workflowIds: workflowIds)
    }

    /// The user-minted entries safe to merge onto a shipped catalog: shipped wins
    /// on both id and target, so minting can never shadow or redefine a shipped
    /// reference.
    private static func mergeableUserReferences(
        _ minted: [ReferenceEntry], shipped: [ReferenceEntry]
    ) -> [ReferenceEntry] {
        let shippedIDs = Set(shipped.map(\.id))
        let shippedTargets = Set(shipped.map(\.target))
        return minted.filter {
            !shippedIDs.contains($0.id) && !shippedTargets.contains($0.target)
        }
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
