import Foundation

/// A deterministic, preview-only view of a simulation fixture.
///
/// `simulate` renders the planned shape of a command without executing it,
/// mirroring the existing `scripts/simulate.mjs` preview behavior.
public struct SimulationPreview: Codable, Equatable, Sendable {
    public let id: String
    public let source: String
    public let modeId: String
    public let summary: String
    public let steps: [String]
}

/// Loads a simulation preview from `<fixturesDirectory>/simulations/<id>.json`.
public enum SimulationPreviewLoader {
    public static func load(id: String, fixturesDirectory: URL) throws -> SimulationPreview {
        let url = fixturesDirectory
            .appendingPathComponent("simulations", isDirectory: true)
            .appendingPathComponent("\(id).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SimulationPreview.self, from: data)
    }
}
