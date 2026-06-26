import Foundation
import Testing

import CerebralCore

/// NIC-26 (part 1): config-backed tool registry, workspace path resolution,
/// event-log tailing, and output rendering used by the `cerebral` CLI.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

private func configDirectory() -> URL {
    repositoryRoot().appendingPathComponent("config", isDirectory: true)
}

// MARK: - Registry (AC-26.1)

@Test("the tool registry loads configured tools sorted by id")
func registryLoadsConfiguredTools() throws {
    let registry = try ConfiguredToolRegistry.load(configDirectory: configDirectory())

    #expect(registry.tools.map(\.id) == registry.tools.map(\.id).sorted())
    let appOpen = registry.tool(id: "app.open")
    #expect(appOpen?.risk == "local_write")
    #expect(appOpen?.availableInPreMac == false)
    #expect(registry.tool(id: "system.status.read") != nil)
}

// MARK: - Rendering (AC-26.2)

@Test("the tool list renders human and JSON forms of the same data")
func toolListRendersBothForms() throws {
    let tools = [
        ConfiguredTool(id: "app.open", risk: "local_write", timeoutMs: 30000, availableInPreMac: false),
        ConfiguredTool(id: "system.status.read", risk: "read_only", timeoutMs: 5000, availableInPreMac: true),
    ]

    let human = ToolListRenderer.humanReadable(tools)
    #expect(human.contains("app.open"))
    #expect(human.contains("local_write"))
    #expect(human.contains("PRE-MAC"))

    let json = try ToolListRenderer.json(tools)
    let decoded = try JSONDecoder().decode([ConfiguredTool].self, from: Data(json.utf8))
    #expect(decoded == tools)
}

// MARK: - Workspace paths (AC-26.3)

@Test("workspace paths resolve to the repository defaults")
func workspacePathsResolveDefaults() throws {
    let root = repositoryRoot()
    let paths = try WorkspacePaths(repositoryRoot: root)

    #expect(paths.configDirectory.lastPathComponent == "config")
    #expect(paths.fixturesDirectory.lastPathComponent == "fixtures")
    #expect(paths.eventLogPath.path.hasSuffix("events.ndjson"))
    #expect(paths.stateRoot.path.contains("development"))
}

@Test("a within-repo state-root override is honored")
func workspaceHonorsOverride() throws {
    let root = repositoryRoot()
    let paths = try WorkspacePaths(
        repositoryRoot: root,
        environment: ["CEREBRAL_STATE_ROOT": ".local/alt-state"]
    )
    #expect(paths.stateRoot.path.hasSuffix("alt-state"))
    #expect(paths.eventLogPath.path.contains("alt-state"))
}

@Test("paths outside the repository or production-looking are rejected")
func workspaceRejectsUnsafePaths() {
    let root = repositoryRoot()
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(repositoryRoot: root, environment: ["CEREBRAL_STATE_ROOT": "/tmp/elsewhere"])
    }
    #expect(throws: WorkspacePathError.self) {
        _ = try WorkspacePaths(repositoryRoot: root, environment: ["CEREBRAL_STATE_ROOT": ".local/production-state"])
    }
}

// MARK: - Event-log tail

@Test("event-log tail returns the last entries and tolerates a missing log")
func eventLogTail() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("cerebral-events-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let log = directory.appendingPathComponent("events.ndjson")

    // Missing log -> no entries.
    #expect(try EventLogReader.tail(log, lines: 5).isEmpty)

    let lines = (1...5).map { "{\"n\":\($0)}" }
    try lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8)

    #expect(try EventLogReader.tail(log, lines: 2) == ["{\"n\":4}", "{\"n\":5}"])
    #expect(try EventLogReader.tail(log, lines: 100).count == 5)

    try FileManager.default.removeItem(at: directory)
}
