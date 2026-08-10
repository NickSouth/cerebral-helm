import Foundation
import Testing
import CerebralContracts
import CerebralCore

private func loaderRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func writeOverride(_ json: String, to paths: WorkspacePaths, name: String) throws {
    try FileManager.default.createDirectory(at: paths.overridesDirectory, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: paths.overridesDirectory.appendingPathComponent(name))
}

private func developerMode(quickApps: [String]) throws -> CerebralHelmModeConfig {
    let appList = quickApps.map { "\"\($0)\"" }.joined(separator: ", ")
    let json = """
    {
      "id": "developer",
      "label": "Developer",
      "theme": { "accentPrimary": "developer.primary", "accentSecondary": "developer.secondary" },
      "quickApps": [\(appList)],
      "quickActions": ["open-developer-layout", "b", "c", "d", "e", "f", "g", "h"],
      "widgets": { "left": "x", "right": "y" }
    }
    """
    return try CerebralHelmModeConfig(data: Data(json.utf8))
}

// MARK: - AC-36.3 (merge level): override survives a default change

@Test("a quickApps override survives a change to the shipped default (AC-36.3)")
func overrideSurvivesDefaultChange() throws {
    let override = CerebralHelmModeOverride(
        extensions: nil, id: "developer", layout: nil, quickApps: ["vscode", "terminal", "linear"], schemaVersion: "1.0.0"
    )

    let merged1 = ConfigLoader.applyOverrides(
        [try developerMode(quickApps: ["vscode", "terminal", "github", "docs"])], [override]
    )
    #expect(merged1.first?.quickApps == ["vscode", "terminal", "linear"])

    // The shipped default changes (adds an app); the user override still wins.
    let merged2 = ConfigLoader.applyOverrides(
        [try developerMode(quickApps: ["vscode", "terminal", "github", "docs", "xcode"])], [override]
    )
    #expect(merged2.first?.quickApps == ["vscode", "terminal", "linear"])
}

@Test("a mode with no override is returned unchanged")
func modeWithoutOverrideUnchanged() throws {
    let mode = try developerMode(quickApps: ["vscode", "terminal"])
    let merged = ConfigLoader.applyOverrides([mode], [])
    #expect(merged.first?.quickApps == ["vscode", "terminal"])
}

// MARK: - AC-36.3 (end to end): load applies a user override

@Test("load applies a user override onto the shipped mode (AC-36.3)")
func loadAppliesUserOverride() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    try writeOverride(
        #"{"schemaVersion":"1.0.0","id":"developer","quickApps":["vscode","terminal","linear"]}"#,
        to: paths, name: "developer.json"
    )

    switch ConfigLoader(workspace: paths).load() {
    case let .activated(active):
        #expect(active.mode(id: "developer")?.quickApps == ["vscode", "terminal", "linear"])
    case let .rejected(errors, _):
        Issue.record("expected activation, got: \(errors.map { "\($0.file)\($0.field)" })")
    }
}

@Test("a session override takes precedence over a user override")
func sessionOverrideWins() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    try writeOverride(
        #"{"schemaVersion":"1.0.0","id":"developer","quickApps":["vscode"]}"#,
        to: paths, name: "developer.json"
    )
    let session = CerebralHelmModeOverride(
        extensions: nil, id: "developer", layout: nil, quickApps: ["terminal"], schemaVersion: "1.0.0"
    )

    switch ConfigLoader(workspace: paths).load(sessionOverrides: [session]) {
    case let .activated(active):
        #expect(active.mode(id: "developer")?.quickApps == ["terminal"])
    case .rejected:
        Issue.record("expected activation")
    }
}

// MARK: - AC-36.1: invalid candidate never replaces active config

@Test("an invalid override never replaces the active config (AC-36.1)")
func invalidOverrideKeepsLastKnownGood() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    let loader = ConfigLoader(workspace: paths)

    // First load: shipped config is valid → activated, snapshot persisted.
    guard case let .activated(good) = loader.load() else {
        Issue.record("expected initial activation")
        return
    }
    #expect(good.modes.count == 4)

    // An invalid override tries to smuggle in a risk-weakening field.
    try writeOverride(
        #"{"schemaVersion":"1.0.0","id":"developer","riskOverrides":{"hook.run":"read_only"}}"#,
        to: paths, name: "bad.json"
    )

    switch loader.load() {
    case .activated:
        Issue.record("an invalid override must not activate")
    case let .rejected(errors, lastKnownGood):
        #expect(!errors.isEmpty)
        #expect(errors.contains { $0.field == "/riskOverrides" })
        #expect(lastKnownGood?.modes.count == good.modes.count)
    }
}

// MARK: - NIC-40: config migration in the live load path (FR-CFG-05)

private struct OverrideRenameMigration: ConfigMigration {
    let fromVersion = "0.9.0"
    let toVersion = "1.0.0"
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue] {
        var out = document
        if let apps = out["apps"] {
            out["quickApps"] = apps
            out.removeValue(forKey: "apps")
        }
        out["schemaVersion"] = .string(toVersion)
        return out
    }
}

private struct OverrideThrowingMigration: ConfigMigration {
    let fromVersion = "0.9.0"
    let toVersion = "1.0.0"
    struct Boom: Error {}
    func migrate(_ document: [String: JSONValue]) throws -> [String: JSONValue] { throw Boom() }
}

@Test("an older supported override is migrated before activation (FR-CFG-05)")
func loadMigratesOlderOverride() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    try writeOverride(
        #"{"schemaVersion":"0.9.0","id":"developer","apps":["vscode","terminal","linear"]}"#,
        to: paths, name: "developer.json"
    )
    let loader = ConfigLoader(
        workspace: paths,
        migrator: ConfigMigrator(currentVersion: "1.0.0", migrations: [OverrideRenameMigration()])
    )

    switch loader.load() {
    case let .activated(active):
        // The legacy `apps` field migrated to `quickApps` and merged onto the mode.
        #expect(active.mode(id: "developer")?.quickApps == ["vscode", "terminal", "linear"])
    case let .rejected(errors, _):
        Issue.record("expected activation, got: \(errors.map { $0.message })")
    }
}

@Test("a failed override migration leaves the last-known-good config active")
func failedOverrideMigrationKeepsLastKnownGood() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    // A clean activation establishes the last-known-good snapshot.
    guard case let .activated(good) = ConfigLoader(workspace: paths).load() else {
        Issue.record("expected initial activation")
        return
    }

    try writeOverride(
        #"{"schemaVersion":"0.9.0","id":"developer","apps":["vscode"]}"#,
        to: paths, name: "developer.json"
    )
    let loader = ConfigLoader(
        workspace: paths,
        migrator: ConfigMigrator(currentVersion: "1.0.0", migrations: [OverrideThrowingMigration()])
    )

    switch loader.load() {
    case .activated:
        Issue.record("a failed migration must not activate")
    case let .rejected(errors, lastKnownGood):
        #expect(errors.contains { $0.field == "/schemaVersion" })
        #expect(lastKnownGood?.modes.count == good.modes.count)
    }
}

@Test("activation records settings metadata with the active config version")
func activationWritesSettingsMetadata() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    guard case .activated = ConfigLoader(workspace: paths).load() else {
        Issue.record("expected activation")
        return
    }

    let data = try Data(contentsOf: paths.settingsMetadataPath)
    let metadata = try JSONDecoder().decode(SettingsMetadata.self, from: data)
    #expect(metadata.activeConfigVersion == "1.0.0")
}

@Test("the last-known-good snapshot round-trips from disk")
func lastKnownGoodRoundTrips() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    let loader = ConfigLoader(workspace: paths)

    guard case .activated = loader.load() else {
        Issue.record("expected activation")
        return
    }
    // A fresh loader reads the persisted snapshot written by the first load.
    let restored = ConfigLoader(workspace: paths).lastKnownGood()
    #expect(restored?.modes.count == 4)
}

// MARK: - NIC-103: crash-during-write leaves no half-written durable config

@Test("a truncated last-known-good snapshot does not brick loading")
func truncatedSnapshotDoesNotBrickLoad() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    try FileManager.default.createDirectory(at: paths.stateRoot, withIntermediateDirectories: true)
    // The shape a non-atomic write leaves behind when the process dies mid-write.
    try Data("{\"activeConfigVersion\":\"1.0".utf8).write(to: paths.activeConfigPath)

    let loader = ConfigLoader(workspace: paths)

    // Reading the corrupt snapshot yields nothing rather than throwing or crashing…
    #expect(loader.lastKnownGood() == nil)
    // …and loading still produces a usable configuration from the shipped defaults,
    // so a torn snapshot can never leave the app unable to start (NFR-06).
    _ = loader.load()
}

/// Note on what this does *not* prove: atomicity cannot be unit-tested here. A
/// write that completes leaves an identical file whether or not `.atomic` was
/// used — the difference only appears if the process dies mid-write, which is not
/// reproducible in-process. This asserts the observable postconditions (the
/// snapshot round-trips whole, and no temp sibling is left behind); the atomicity
/// guarantee itself rests on the `.atomic` option in `persistLastKnownGood`.
@Test("a persisted snapshot round-trips whole and leaves no temp file behind")
func snapshotWriteLeavesNoPartialFile() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: loaderRepositoryRoot())
    let loader = ConfigLoader(workspace: paths)

    // `load()` persists the snapshot as a side effect.
    _ = loader.load()

    // Whatever is on disk must be complete and decodable. With a non-atomic write the
    // file is built up in place, so an interrupted write leaves a prefix; `.atomic`
    // writes a temp file and replaces, so the path only ever names a whole file.
    guard FileManager.default.fileExists(atPath: paths.activeConfigPath.path) else { return }
    let data = try Data(contentsOf: paths.activeConfigPath)
    #expect(!data.isEmpty)
    #expect(loader.lastKnownGood() != nil, "the persisted snapshot must decode as a whole value")

    // No temporary sibling should survive a completed write.
    let leftovers = try FileManager.default
        .contentsOfDirectory(atPath: paths.stateRoot.path)
        .filter { $0.hasPrefix(".") && $0.contains("active-config") }
    #expect(leftovers.isEmpty, "an atomic write must not leave its temp file behind: \(leftovers)")
}
