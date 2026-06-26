import Foundation

/// A configured tool as declared in `config/tools/*.json`.
///
/// This is the minimal, config-backed view used by the CLI's `tools list`. It is
/// also the stricter-only overlay consumed by ``ToolRegistryBuilder``: the rich
/// ``CerebralHelmToolDescriptor`` is authoritative (ADR-003, NIC-28), and an
/// overlay may only tighten operational limits, never weaken them.
public struct ConfiguredTool: Codable, Equatable, Sendable {
    public let id: String
    public let risk: String
    public let timeoutMs: Int
    public let availableInPreMac: Bool

    public init(id: String, risk: String, timeoutMs: Int, availableInPreMac: Bool) {
        self.id = id
        self.risk = risk
        self.timeoutMs = timeoutMs
        self.availableInPreMac = availableInPreMac
    }
}

/// Read-only registry of configured tools, sorted by id.
public struct ConfiguredToolRegistry: Sendable {
    public let tools: [ConfiguredTool]

    public init(tools: [ConfiguredTool]) {
        self.tools = tools.sorted { $0.id < $1.id }
    }

    public func tool(id: String) -> ConfiguredTool? {
        tools.first { $0.id == id }
    }

    /// Loads the registry from `<configDirectory>/tools/*.json`.
    public static func load(configDirectory: URL) throws -> ConfiguredToolRegistry {
        let toolsDirectory = configDirectory.appendingPathComponent("tools", isDirectory: true)
        guard FileManager.default.fileExists(atPath: toolsDirectory.path) else {
            return ConfiguredToolRegistry(tools: [])
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: toolsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        let tools = try files.map { try decoder.decode(ConfiguredTool.self, from: Data(contentsOf: $0)) }
        return ConfiguredToolRegistry(tools: tools)
    }
}
