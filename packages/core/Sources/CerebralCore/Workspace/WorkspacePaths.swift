import Foundation

/// A path that fell outside the allowed workspace.
public enum WorkspacePathError: Error, Equatable {
    case outsideRepository(String)
    case productionLikePath(String)
}

/// Resolves the development roots the CLI works against, mirroring the Node
/// `workspace-roots.mjs` conventions so both toolchains agree on locations.
///
/// All resolved paths must stay inside the repository and must not look like a
/// personal/production location — tests and dev tooling never touch real
/// production state (PRD §7.8 FR-CFG-06).
public struct WorkspacePaths: Sendable {
    public let repositoryRoot: URL
    public let configDirectory: URL
    public let fixturesDirectory: URL
    public let stateRoot: URL
    public let eventLogPath: URL

    public init(repositoryRoot: URL, environment: [String: String] = [:]) throws {
        let root = repositoryRoot.standardizedFileURL
        self.repositoryRoot = root
        self.configDirectory = root.appendingPathComponent("config", isDirectory: true)
        self.fixturesDirectory = root.appendingPathComponent("fixtures", isDirectory: true)

        let defaultStateRoot = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("development", isDirectory: true)
        let stateRoot = Self.resolve(environment["CEREBRAL_STATE_ROOT"], default: defaultStateRoot, relativeTo: root)
        try Self.validate(stateRoot, root: root, label: "State root")
        self.stateRoot = stateRoot

        let defaultEventLog = stateRoot
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("events.ndjson")
        let eventLogPath = Self.resolve(environment["CEREBRAL_EVENT_LOG_PATH"], default: defaultEventLog, relativeTo: root)
        try Self.validate(eventLogPath, root: root, label: "Event log path")
        self.eventLogPath = eventLogPath
    }

    private static func resolve(_ configured: String?, default fallback: URL, relativeTo root: URL) -> URL {
        guard let configured, !configured.isEmpty else { return fallback.standardizedFileURL }
        if isAbsolute(configured) {
            return URL(fileURLWithPath: configured).standardizedFileURL
        }
        return root.appendingPathComponent(configured).standardizedFileURL
    }

    private static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        // Windows drive-letter path, e.g. C:\ or C:/
        let characters = Array(path)
        return characters.count >= 2 && characters[1] == ":" && characters[0].isLetter
    }

    private static func validate(_ url: URL, root: URL, label: String) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw WorkspacePathError.outsideRepository("\(label) must stay inside the repository: \(targetPath)")
        }
        let lowered = targetPath.lowercased()
        for segment in ["production", "personal-prod", "personal_production"] where lowered.contains(segment) {
            throw WorkspacePathError.productionLikePath("\(label) must not look like a production path: \(targetPath)")
        }
    }
}
