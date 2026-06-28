import Foundation

/// The data environment a workspace resolves against (FR-CFG-06).
///
/// Each environment keeps its state on a separate root so development and test
/// runs can never open or mutate staging or personal production data:
/// - `test`: an isolated, ephemeral root (use ``WorkspacePaths/temporary(repositoryRoot:)``).
/// - `development`: the in-repo `.local/development` root (the default).
/// - `staging`: an explicit, isolated, sanitized clone — never the real production path.
/// - `production`: an explicit, user-selected root; the only environment allowed
///   to resemble a personal/production location.
public enum WorkspaceEnvironment: String, Sendable {
    case test
    case development
    case staging
    case production
}

/// A path that fell outside the rules for its environment.
public enum WorkspacePathError: Error, Equatable {
    case outsideRepository(String)
    case productionLikePath(String)
    case explicitRootRequired(String)
    case unknownEnvironment(String)
}

/// Resolves the data roots the CLI/app works against for a given environment,
/// mirroring the Node `workspace-roots.mjs` development conventions so both
/// toolchains agree on the development layout.
///
/// `development` and `test` fail closed: their roots must not resemble a
/// personal/production location, and development stays inside the repository
/// while test is confined to the repository or the OS temporary directory.
/// `staging` and `production` require an explicit, user-selected root and may
/// live outside the repository (PRD §7.8 FR-CFG-06).
public struct WorkspacePaths: Sendable {
    public let environment: WorkspaceEnvironment
    public let repositoryRoot: URL
    public let configDirectory: URL
    public let fixturesDirectory: URL
    /// Directory of authoritative rich tool descriptors (`config/tools/descriptors`).
    public let toolDescriptorsDirectory: URL
    public let stateRoot: URL
    /// Directory of per-mode user override files (`<stateRoot>/overrides`).
    public let overridesDirectory: URL
    /// Last-known-good activated config snapshot (`<stateRoot>/active-config.json`).
    public let activeConfigPath: URL
    /// Config version / rollback metadata (`<stateRoot>/settings-metadata.json`).
    public let settingsMetadataPath: URL
    /// Active mode id, persisted separately from context (`<stateRoot>/active-mode.json`).
    public let activeModePath: URL
    /// Active project/context, persisted separately from mode (`<stateRoot>/active-context.json`).
    public let activeContextPath: URL
    /// Append-only mode session history (`<stateRoot>/sessions/mode-sessions.ndjson`).
    public let modeSessionLogPath: URL
    public let eventLogPath: URL

    /// Resolves workspace paths. The environment is selected by `CEREBRAL_ENV`
    /// (default `development`); `CEREBRAL_STATE_ROOT` / `CEREBRAL_EVENT_LOG_PATH`
    /// override the resolved locations.
    public init(repositoryRoot: URL, environment processEnvironment: [String: String] = [:]) throws {
        let root = repositoryRoot.standardizedFileURL
        let env = try Self.environment(from: processEnvironment["CEREBRAL_ENV"])

        self.environment = env
        self.repositoryRoot = root
        self.configDirectory = root.appendingPathComponent("config", isDirectory: true)
        self.fixturesDirectory = root.appendingPathComponent("fixtures", isDirectory: true)
        self.toolDescriptorsDirectory = root
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("descriptors", isDirectory: true)

        let stateRoot = try Self.resolveStateRoot(
            processEnvironment["CEREBRAL_STATE_ROOT"], environment: env, root: root
        )
        try Self.validate(stateRoot, root: root, environment: env, label: "State root")
        self.stateRoot = stateRoot
        self.overridesDirectory = stateRoot.appendingPathComponent("overrides", isDirectory: true)
        self.activeConfigPath = stateRoot.appendingPathComponent("active-config.json")
        self.settingsMetadataPath = stateRoot.appendingPathComponent("settings-metadata.json")
        self.activeModePath = stateRoot.appendingPathComponent("active-mode.json")
        self.activeContextPath = stateRoot.appendingPathComponent("active-context.json")
        self.modeSessionLogPath = stateRoot
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("mode-sessions.ndjson")

        let eventLogPath: URL
        if let configured = processEnvironment["CEREBRAL_EVENT_LOG_PATH"], !configured.isEmpty {
            eventLogPath = Self.resolvePath(configured, relativeTo: root)
        } else {
            eventLogPath = stateRoot
                .appendingPathComponent("events", isDirectory: true)
                .appendingPathComponent("events.ndjson")
                .standardizedFileURL
        }
        try Self.validate(eventLogPath, root: root, environment: env, label: "Event log path")
        self.eventLogPath = eventLogPath
    }

    /// Builds an isolated, ephemeral workspace for automated tests (AC-41.1).
    ///
    /// The state root is a unique directory under the OS temporary location, so a
    /// test run can never open or mutate development, staging, or personal
    /// production state.
    public static func temporary(repositoryRoot: URL) throws -> WorkspacePaths {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cerebral-test-\(UUID().uuidString)", isDirectory: true)
        return try WorkspacePaths(
            repositoryRoot: repositoryRoot,
            environment: [
                "CEREBRAL_ENV": "test",
                "CEREBRAL_STATE_ROOT": tempRoot.standardizedFileURL.path
            ]
        )
    }

    // MARK: - Environment

    private static func environment(from raw: String?) throws -> WorkspaceEnvironment {
        guard let raw, !raw.isEmpty else { return .development }
        guard let env = WorkspaceEnvironment(rawValue: raw) else {
            throw WorkspacePathError.unknownEnvironment(
                "Unknown CEREBRAL_ENV \"\(raw)\"; expected test, development, staging, or production."
            )
        }
        return env
    }

    // MARK: - Resolution

    private static func resolveStateRoot(
        _ configured: String?, environment: WorkspaceEnvironment, root: URL
    ) throws -> URL {
        if let configured, !configured.isEmpty {
            return resolvePath(configured, relativeTo: root)
        }
        switch environment {
        case .development:
            return defaultRoot(root, "development")
        case .test:
            return defaultRoot(root, "test")
        case .staging, .production:
            // No implicit default: staging/production state is always explicitly
            // selected so it can never be created by accident (AC-41.2, AC-41.3).
            throw WorkspacePathError.explicitRootRequired(
                "\(environment.rawValue) requires an explicit CEREBRAL_STATE_ROOT (user-selected)."
            )
        }
    }

    private static func defaultRoot(_ root: URL, _ name: String) -> URL {
        root.appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .standardizedFileURL
    }

    private static func resolvePath(_ configured: String, relativeTo root: URL) -> URL {
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

    // MARK: - Validation

    private static func validate(
        _ url: URL, root: URL, environment: WorkspaceEnvironment, label: String
    ) throws {
        let targetPath = url.standardizedFileURL.path

        // Production is the only environment allowed to resemble a personal /
        // production location; every other environment fails closed.
        if environment != .production {
            let lowered = targetPath.lowercased()
            for segment in ["production", "personal-prod", "personal_production"] where lowered.contains(segment) {
                throw WorkspacePathError.productionLikePath(
                    "\(label) must not look like a production path in \(environment.rawValue): \(targetPath)"
                )
            }
        }

        let rootPath = root.standardizedFileURL.path
        switch environment {
        case .development:
            guard isInside(targetPath, rootPath) else {
                throw WorkspacePathError.outsideRepository(
                    "\(label) must stay inside the repository in development: \(targetPath)"
                )
            }
        case .test:
            let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
            guard isInside(targetPath, rootPath) || isInside(targetPath, tempPath) else {
                throw WorkspacePathError.outsideRepository(
                    "\(label) for tests must stay inside the repository or a temporary directory: \(targetPath)"
                )
            }
        case .staging, .production:
            break // explicit, user-selected; may live outside the repository
        }
    }

    private static func isInside(_ targetPath: String, _ basePath: String) -> Bool {
        targetPath == basePath || targetPath.hasPrefix(basePath + "/")
    }
}
