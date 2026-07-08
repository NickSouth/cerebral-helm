/// A single named reference the parser can resolve (an app, URL, or hook).
///
/// `target` is provider-neutral payload data (a bundle id, URL, or hook script
/// path). The parser resolves references but never executes them.
public struct ReferenceEntry: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let target: String

    public init(id: String, label: String, target: String) {
        self.id = id
        self.label = label
        self.target = target
    }
}

/// The resolved, in-memory reference catalogs the parser resolves against.
///
/// This is a pure value type so the parser stays deterministic and testable
/// without filesystem access; loading from `config/references` is the loader's
/// job (``ReferenceCatalogLoader``).
public struct CommandReferences: Sendable {
    public let apps: [String: ReferenceEntry]
    public let urls: [String: ReferenceEntry]
    public let hooks: [String: ReferenceEntry]
    public let modeIds: Set<String>
    /// Configured workflow / quick-action ids (`config/workflows/*.json`),
    /// resolvable through the `run <action>` verb.
    public let workflowIds: Set<String>

    public init(
        apps: [ReferenceEntry] = [],
        urls: [ReferenceEntry] = [],
        hooks: [ReferenceEntry] = [],
        modeIds: [String] = [],
        workflowIds: [String] = []
    ) {
        self.apps = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.urls = Dictionary(urls.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.hooks = Dictionary(hooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.modeIds = Set(modeIds)
        self.workflowIds = Set(workflowIds)
    }
}
