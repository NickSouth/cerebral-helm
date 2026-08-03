import Foundation
import Testing

import CerebralCore
import CerebralShared
import CerebralKnowledge

/// NIC-162: the knowledge read port — listing and reading the durable Markdown.
///
/// The through-line of every test here is that the *files* are the source of
/// truth: a note CerebralHelm never wrote must list and read exactly like one it
/// did, and nothing outside the knowledge root is reachable.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-library-\(UUID().uuidString)", isDirectory: true)
}

/// Writes a file verbatim, creating intermediate folders — the "authored
/// somewhere else" case, deliberately bypassing capture.
@discardableResult
private func write(_ content: String, to relativePath: String, under root: URL) throws -> URL {
    let url = relativePath.split(separator: "/").map(String.init).reduce(root) {
        $0.appendingPathComponent($1)
    }
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(content.utf8).write(to: url)
    return url
}

private func service(_ root: URL, at now: Date = t0) -> MarkdownKnowledgeService {
    MarkdownKnowledgeService(rootURL: root, clock: FixedClock(now))
}

// MARK: - list

@Test("a note authored outside CerebralHelm is listed without any rebuild (FR-KNW-01)")
func listIncludesExternallyAuthoredNotes() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = InMemoryNoteSearchIndex()
    let knowledge = MarkdownKnowledgeService(rootURL: root, searchIndex: index, clock: FixedClock(t0))

    _ = try await knowledge.capture(
        NoteCaptureRequest(title: "Captured", body: "from the palette", kind: "note", project: nil, sensitivity: nil)
    )
    // No frontmatter, a filename CerebralHelm would never mint: an Obsidian note.
    try write("# Hull plating\n\nnotes on rivets\n", to: "inbox/Hull Plating.md", under: root)

    let listed = try await knowledge.list(NoteListRequest(limit: nil))

    #expect(listed.entries.count == 2)
    let external = try #require(listed.entries.first { $0.path == "inbox/Hull Plating.md" })
    // The index only knows what capture wrote, so search cannot see it yet — the
    // listing reads the files and can.
    #expect(try await knowledge.search(NoteSearchRequest(query: "rivets", limit: nil)).hits.isEmpty)
    #expect(external.title == "Hull Plating")   // no frontmatter title: the filename is the title
    #expect(external.noteID == nil)             // and it carries no CerebralHelm id
    #expect(external.folder == "inbox")
}

@Test("the listing cites the knowledge root as its source location")
func listReportsRoot() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("body\n", to: "inbox/one.md", under: root)

    let listed = try await service(root).list(NoteListRequest(limit: nil))

    #expect(listed.root == root.path)
    #expect(listed.entries.map(\.path) == ["inbox/one.md"])
}

@Test("notes list most-recently-changed first, by frontmatter or by file date")
func listOrdersByRecency() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let older = ISO8601Timestamp.string(from: t0)
    let newer = ISO8601Timestamp.string(from: t0.addingTimeInterval(3600))
    try write("---\nid: \"a\"\nupdated: \"\(older)\"\n---\n\nold\n", to: "inbox/a.md", under: root)
    try write("---\nid: \"b\"\nupdated: \"\(newer)\"\n---\n\nnew\n", to: "inbox/b.md", under: root)
    // No frontmatter at all: recency falls back to the file's modification date,
    // which an edit in another editor moves.
    let untracked = try write("plain\n", to: "inbox/c.md", under: root)
    try FileManager.default.setAttributes(
        [.modificationDate: t0.addingTimeInterval(7200)], ofItemAtPath: untracked.path
    )

    let listed = try await service(root).list(NoteListRequest(limit: nil))

    #expect(listed.entries.map(\.path) == ["inbox/c.md", "inbox/b.md", "inbox/a.md"])
    #expect(listed.entries.last?.updated == older)
}

@Test("a note in projects/<name> reports its project even without frontmatter")
func listDerivesProjectFromHierarchy() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("scope\n", to: "projects/atlas/kickoff.md", under: root)
    try write("reading\n", to: "areas/health/sleep.md", under: root)

    let entries = try await service(root).list(NoteListRequest(limit: nil)).entries
    let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })

    #expect(byPath["projects/atlas/kickoff.md"]?.project == "atlas")
    #expect(byPath["projects/atlas/kickoff.md"]?.folder == "projects/atlas")
    // Only the projects hierarchy names a project; an area is a folder, not one.
    #expect(byPath["areas/health/sleep.md"]?.project == nil)
    #expect(byPath["areas/health/sleep.md"]?.folder == "areas/health")
}

@Test("the limit truncates and says so")
func listTruncatesAtLimit() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<3 { try write("n\(index)\n", to: "inbox/n\(index).md", under: root) }

    let capped = try await service(root).list(NoteListRequest(limit: 2))
    #expect(capped.entries.count == 2)
    #expect(capped.truncated)
    // The total is the library, not the request: a caller asking for two notes
    // still learns there are three.
    #expect(capped.total == 3)

    let whole = try await service(root).list(NoteListRequest(limit: 10))
    #expect(whole.entries.count == 3)
    #expect(!whole.truncated)
    #expect(whole.total == 3)
}

@Test("an editor's hidden state is not a note (Obsidian .obsidian/ and .trash/)")
func listSkipsHiddenEditorState() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = InMemoryNoteSearchIndex()
    let knowledge = MarkdownKnowledgeService(rootURL: root, searchIndex: index, clock: FixedClock(t0))

    try write("real\n", to: "inbox/real.md", under: root)
    try write("deleted in Obsidian\n", to: ".trash/gone.md", under: root)
    try write("template\n", to: ".obsidian/templates/daily.md", under: root)

    #expect(try await knowledge.list(NoteListRequest(limit: nil)).entries.map(\.path) == ["inbox/real.md"])

    // The same exclusion governs the rebuilt index, so a trashed note cannot come
    // back as a search hit either.
    try knowledge.rebuild()
    let hits = try await knowledge.search(NoteSearchRequest(query: "", limit: nil)).hits
    #expect(hits.map(\.path) == ["inbox/real.md"])
}

@Test("an empty root lists nothing; a missing root is unavailable, not empty (FR-KNW-07)")
func listDistinguishesEmptyFromMissing() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // Missing: the caller must be able to say so rather than showing "no notes".
    await #expect(throws: KnowledgeServiceError.rootUnavailable) {
        _ = try await service(root).list(NoteListRequest(limit: nil))
    }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let listed = try await service(root).list(NoteListRequest(limit: nil))
    #expect(listed.entries.isEmpty)
    #expect(!listed.truncated)
}

// MARK: - read

@Test("read returns the frontmatter, the body, and the note's source path")
func readReturnsFrontmatterBodyAndPath() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let knowledge = service(root)
    let captured = try await knowledge.capture(
        NoteCaptureRequest(title: "Rivet log", body: "hull plating notes", kind: "note", project: "atlas", sensitivity: nil)
    )

    let note = try await knowledge.read(NoteReadRequest(path: captured.path))

    #expect(note.path == captured.path)
    #expect(note.root == root.path)
    #expect(note.title == "Rivet log")
    #expect(note.noteID == captured.noteID)
    #expect(note.body.contains("hull plating notes"))
    // Frontmatter is surfaced as parsed, including keys beyond the projected fields.
    #expect(note.frontmatter["project"] == "atlas")
    #expect(note.frontmatter["sensitivity"] == "private")
    #expect(note.updated == note.frontmatter["updated"])
}

@Test("a note with no frontmatter reads as itself, titled by filename")
func readHandlesPlainMarkdown() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("# Sleep\n\neight hours\n", to: "areas/health/Sleep Log.md", under: root)

    let note = try await service(root).read(NoteReadRequest(path: "areas/health/Sleep Log.md"))

    #expect(note.title == "Sleep Log")
    #expect(note.noteID == nil)
    #expect(note.frontmatter.isEmpty)
    #expect(note.body == "# Sleep\n\neight hours\n")
}

@Test("a path that climbs out of the root is refused, not read")
func readRefusesTraversal() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // A real, readable Markdown file outside the root — the thing traversal targets.
    let outside = root.deletingLastPathComponent()
        .appendingPathComponent("cerebral-outside-\(UUID().uuidString).md")
    try Data("secrets\n".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }

    for attempt in [
        "../\(outside.lastPathComponent)",
        "inbox/../../\(outside.lastPathComponent)",
        outside.path,
        "..%2Fescape.md"
    ] {
        await #expect(throws: KnowledgeServiceError.self) {
            _ = try await service(root).read(NoteReadRequest(path: attempt))
        }
    }
}

@Test("a symlink pointing outside the root is refused (the resolved location decides)")
func readRefusesSymlinkEscape() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("inbox"), withIntermediateDirectories: true
    )
    let outside = root.deletingLastPathComponent()
        .appendingPathComponent("cerebral-outside-\(UUID().uuidString).md")
    try Data("secrets\n".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }

    // A note-shaped path inside the root that actually points elsewhere.
    let link = root.appendingPathComponent("inbox").appendingPathComponent("escape.md")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

    await #expect(throws: KnowledgeServiceError.self) {
        _ = try await service(root).read(NoteReadRequest(path: "inbox/escape.md"))
    }
}

@Test("only Markdown is a note, and a missing note is not found")
func readRefusesNonMarkdownAndMissing() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try write("id: local\nsecret: value\n", to: "inbox/config.yaml", under: root)

    for attempt in ["inbox/config.yaml", "inbox/nothing.md", "", "inbox"] {
        await #expect(throws: KnowledgeServiceError.self) {
            _ = try await service(root).read(NoteReadRequest(path: attempt))
        }
    }
}

@Test("reading against a missing root is unavailable, not not-found (FR-KNW-07)")
func readReportsMissingRoot() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    await #expect(throws: KnowledgeServiceError.rootUnavailable) {
        _ = try await service(root).read(NoteReadRequest(path: "inbox/anything.md"))
    }
}

@Test("a not-found read maps to recovery guidance that promises no change")
func notFoundMapsToRecoveryGuidance() {
    let diagnostic = RecoveryDiagnostic.forKnowledge(.noteNotFound("No note at inbox/gone.md in the knowledge root."))

    #expect(diagnostic.store == "knowledge")
    #expect(diagnostic.code == "knowledge_note_missing")
    #expect(!diagnostic.guidance.isEmpty)
}
