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
    /// Which model serves each capability profile (NIC-243), or nil when no model is configured.
    ///
    /// Optional, and it must stay optional: this snapshot is persisted as the last-known-good
    /// configuration, so a required field would fail to decode every snapshot written before this
    /// existed — silently discarding a working configuration, which is exactly what the
    /// last-known-good mechanism is there to prevent.
    public let modelProfiles: CerebralHelmModelProfileCatalog?

    public init(
        defaults: CerebralHelmApplicationDefaults,
        modes: [CerebralHelmModeConfig],
        agents: [CerebralHelmAgentSurfaceConfig],
        toolIDs: [String],
        modelProfiles: CerebralHelmModelProfileCatalog? = nil
    ) {
        self.defaults = defaults
        self.modes = modes
        self.agents = agents
        self.toolIDs = toolIDs
        self.modelProfiles = modelProfiles
    }

    /// The resolved profile catalog in the port's own vocabulary, or nil when none is configured.
    public var modelProfileCatalog: ModelProfileCatalog? {
        modelProfiles.map(ModelProfileCatalog.init)
    }

    /// The merged mode config for `id`, or nil if no such mode is configured.
    public func mode(id: String) -> CerebralHelmModeConfig? {
        modes.first { $0.id == id }
    }
}
