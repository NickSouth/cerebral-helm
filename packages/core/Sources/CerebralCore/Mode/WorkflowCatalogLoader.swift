import Foundation
import CerebralContracts

/// Loads workflow / quick-action definitions keyed by id.
///
/// Two sources merge into one catalog:
/// - Static `workflows/*.json` files. Strict decoding is the gate: a malformed or
///   incomplete definition fails to decode and aborts the load (consistent with
///   ``ToolDescriptorCatalog``), so a broken workflow never reaches the planner.
/// - Synthesized `open-<mode>-layout` workflows, one per mode that carries an
///   authored `layout` (NIC-142). The layout is the single source of truth for a
///   mode's layout-open behavior, so a synthesized entry **overrides** any static
///   file of the same id. This one loader feeds both the action planner and the
///   parser's `workflowIds`, so a layout-driven action resolves everywhere.
///
/// A missing directory degrades to an empty file set rather than failing, so a
/// config without workflow files does not disable the command surface (PRD §4.6).
/// Files are read in name order for determinism. Risk lives on tool descriptors,
/// never on a workflow, so a workflow cannot weaken policy regardless of what it
/// declares.
public enum WorkflowCatalogLoader {
    public static func load(configDirectory: URL) throws -> [String: CerebralHelmWorkflowDefinition] {
        var catalog = try loadStaticFiles(configDirectory)

        // Synthesize each mode's layout-open workflow from its authored layout,
        // overriding any static file of the same id (the layout is authoritative).
        for (modeID, layout) in ModeLayoutCatalog.load(configDirectory: configDirectory) {
            let synthesized = try LayoutWorkflowSynthesizer.workflow(modeID: modeID, layout: layout)
            catalog[synthesized.id] = synthesized
        }
        return catalog
    }

    private static func loadStaticFiles(_ configDirectory: URL) throws -> [String: CerebralHelmWorkflowDefinition] {
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
