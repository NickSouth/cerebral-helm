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
        extensions: nil, id: "developer", quickApps: ["vscode", "terminal", "linear"], schemaVersion: "1.0.0"
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
        extensions: nil, id: "developer", quickApps: ["terminal"], schemaVersion: "1.0.0"
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
