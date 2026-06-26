import Foundation
import CerebralContracts

/// Loads rich tool descriptors from disk.
///
/// Rich descriptors are the source of truth for the registry (NIC-28). Strict
/// decoding is the validation gate: a descriptor missing required policy metadata
/// — risk, confirmation policy, schemas, availability — fails to decode and
/// aborts the load, so it can never reach the registry (AC-28.1).
public enum ToolDescriptorCatalog {
    /// Strictly decodes every `*.json` descriptor in `directory`, ordered by file
    /// name for determinism. Throws on the first malformed or incomplete file.
    public static func loadDescriptors(directory: URL) throws -> [CerebralHelmToolDescriptor] {
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        return try files.map { try decoder.decode(CerebralHelmToolDescriptor.self, from: Data(contentsOf: $0)) }
    }
}
