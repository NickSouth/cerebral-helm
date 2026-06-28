import Foundation
import CerebralContracts

/// Loads workflow / quick-action definitions from `workflows/*.json` under a
/// config directory, keyed by id.
///
/// Strict decoding is the gate: a malformed or incomplete definition fails to
/// decode and aborts the load (consistent with ``ToolDescriptorCatalog``), so a
/// broken workflow never reaches the planner. A missing directory degrades to an
/// empty catalog rather than failing, so a config without workflows does not
/// disable the command surface (PRD §4.6). Files are read in name order for
/// determinism. Risk lives on tool descriptors, never on a workflow, so a
/// workflow cannot weaken policy regardless of what it declares.
public enum WorkflowCatalogLoader {
    public static func load(configDirectory: URL) throws -> [String: CerebralHelmWorkflowDefinition] {
        let directory = configDirectory.appendingPathComponent("workflows", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }

        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        var catalog: [String: CerebralHelmWorkflowDefinition] = [:]
        for file in files {
            let definition = try decoder.decode(CerebralHelmWorkflowDefinition.self, from: Data(contentsOf: file))
            catalog[definition.id] = definition
        }
        return catalog
    }
}
