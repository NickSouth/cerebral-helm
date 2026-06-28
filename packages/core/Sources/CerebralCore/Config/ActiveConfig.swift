import CerebralContracts

/// An immutable, validated configuration snapshot — the result of merging the
/// layered config (defaults plus overrides) and the unit the runtime reads from.
///
/// It is persisted as the last-known-good snapshot so an invalid later candidate
/// never replaces a working configuration (FR-CFG-02).
public struct ActiveConfig: Codable {
    public let defaults: CerebralHelmApplicationDefaults
    public let modes: [CerebralHelmModeConfig]
    public let agents: [CerebralHelmAgentSurfaceConfig]
    public let toolIDs: [String]

    public init(
        defaults: CerebralHelmApplicationDefaults,
        modes: [CerebralHelmModeConfig],
        agents: [CerebralHelmAgentSurfaceConfig],
        toolIDs: [String]
    ) {
        self.defaults = defaults
        self.modes = modes
        self.agents = agents
        self.toolIDs = toolIDs
    }

    /// The merged mode config for `id`, or nil if no such mode is configured.
    public func mode(id: String) -> CerebralHelmModeConfig? {
        modes.first { $0.id == id }
    }
}
