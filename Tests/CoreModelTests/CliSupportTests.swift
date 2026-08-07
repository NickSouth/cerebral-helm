import Foundation
import Testing

import CerebralContracts
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

// MARK: - Knowledge read surfaces (NIC-162)

private func sampleListing(
    notes: [NoteListItem],
    truncated: Bool = false
) -> CerebralHelmNoteListOutput {
    CerebralHelmNoteListOutput(
        notes: notes, root: "/Users/fixture/knowledge",
        // A truncated listing carries more notes than it shows.
        total: truncated ? notes.count + 3 : notes.count, truncated: truncated
    )
}

private func capturedNote() -> NoteListItem {
    NoteListItem(
        folder: "projects/atlas", noteID: "ch-note-001", path: "projects/atlas/kickoff.md",
        project: "atlas", sensitivity: .sensitivityPrivate, title: "Atlas kickoff",
        updated: "2026-06-23T18:04:00Z"
    )
}

/// A note authored outside CerebralHelm: no id, no frontmatter date.
private func externalNote() -> NoteListItem {
    NoteListItem(
        folder: "inbox", noteID: nil, path: "inbox/Hull Plating.md",
        project: nil, sensitivity: nil, title: "Hull Plating", updated: nil
    )
}

@Test("the note listing renders human and JSON forms of the same data (NIC-162)")
func noteListRendersBothForms() throws {
    let listing = sampleListing(notes: [capturedNote(), externalNote()])

    let human = NoteLibraryRenderer.humanReadable(list: listing)
    #expect(human.contains("2 notes in /Users/fixture/knowledge"))
    #expect(human.contains("projects/atlas/kickoff.md"))
    #expect(human.contains("Hull Plating"))
    // A note with no readable date says so rather than borrowing a plausible one.
    #expect(human.contains("unknown"))
    #expect(!human.contains("Truncated"))

    // The JSON form is the tool output verbatim, so it round-trips.
    let json = try NoteLibraryRenderer.json(list: listing)
    let decoded = try CerebralHelmNoteListOutput(data: Data(json.utf8))
    #expect(decoded.notes.map(\.path) == listing.notes.map(\.path))
    #expect(decoded.root == listing.root)
}

@Test("an empty knowledge root renders as an empty library at a named location")
func noteListRendersEmptyHonestly() {
    let human = NoteLibraryRenderer.humanReadable(list: sampleListing(notes: []))

    #expect(human == "No notes in /Users/fixture/knowledge.")
}

@Test("a truncated listing counts the library, not its own rows")
func noteListReportsTruncation() {
    // One row shown, four notes on disk.
    let human = NoteLibraryRenderer.humanReadable(list: sampleListing(notes: [capturedNote()], truncated: true))

    // Counting the rows would understate the library as "1 note".
    #expect(human.contains("4 notes in"))
    #expect(human.contains("Showing 1 of 4"))
}

@Test("a single-note library reads in the singular")
func noteListSingularCount() {
    let human = NoteLibraryRenderer.humanReadable(list: sampleListing(notes: [capturedNote()]))

    #expect(human.contains("1 note in"))
    #expect(!human.contains("Showing"))
}

@Test("a note renders with its source path, frontmatter, and body (NIC-162)")
func noteReadRendersBothForms() throws {
    let note = CerebralHelmNoteReadOutput(
        body: "hull plating notes\n",
        frontmatter: ["title": "Atlas kickoff", "project": "atlas", "id": "ch-note-001"],
        noteID: "ch-note-001",
        path: "projects/atlas/kickoff.md",
        root: "/Users/fixture/knowledge",
        title: "Atlas kickoff",
        updated: "2026-06-23T18:04:00Z"
    )

    let human = NoteLibraryRenderer.humanReadable(note: note)
    // The full source location, so the reader can open the file itself.
    #expect(human.contains("/Users/fixture/knowledge/projects/atlas/kickoff.md"))
    #expect(human.contains("project: atlas"))
    #expect(human.contains("hull plating notes"))

    let json = try NoteLibraryRenderer.json(note: note)
    let decoded = try CerebralHelmNoteReadOutput(data: Data(json.utf8))
    #expect(decoded.body == note.body)
    #expect(decoded.frontmatter == note.frontmatter)
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
