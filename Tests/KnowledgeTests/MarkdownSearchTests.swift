import Foundation
import Testing

import CerebralCore
import CerebralShared
import CerebralKnowledge

/// NIC-45 (PRE-DATA-3): index-backed search and rebuild (FR-KNW-04/06, NFR-09).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-search-\(UUID().uuidString)", isDirectory: true)
}

@Test("a captured note is findable and every hit cites its source path (AC-45.1, AC-45.2)")
func captureIsFindableWithPath() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = MarkdownKnowledgeService(rootURL: root, searchIndex: InMemoryNoteSearchIndex(), clock: FixedClock(t0))

    _ = try await service.capture(
        NoteCaptureRequest(title: "Captured note", body: "rivet the hull", kind: "note", project: nil, sensitivity: nil)
    )
    let result = try await service.search(NoteSearchRequest(query: "rivet", limit: nil))

    #expect(result.hits.count == 1)
    let hit = try #require(result.hits.first)
    #expect(!hit.path.isEmpty)            // AC-45.2: every result cites a source path
    #expect(hit.path.hasSuffix(".md"))
    #expect(hit.sensitivity == "private")
}

@Test("deleting the index and rebuilding from files preserves results (AC-45.3)")
func rebuildPreservesResults() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = InMemoryNoteSearchIndex()
    let service = MarkdownKnowledgeService(rootURL: root, searchIndex: index, clock: FixedClock(t0, step: 1))

    _ = try await service.capture(NoteCaptureRequest(title: "Captured note", body: "alpha rivet", kind: "note", project: nil, sensitivity: nil))
    _ = try await service.capture(NoteCaptureRequest(title: "Captured note", body: "beta rivet", kind: "note", project: nil, sensitivity: nil))
    let before = try await service.search(NoteSearchRequest(query: "rivet", limit: nil))
    #expect(before.hits.count == 2)

    // Delete the derived index entirely; search now finds nothing.
    try index.deleteAll()
    #expect(try await service.search(NoteSearchRequest(query: "rivet", limit: nil)).hits.isEmpty)

    // Rebuild from the Markdown files (the source of truth) restores the results.
    try service.rebuild()
    let after = try await service.search(NoteSearchRequest(query: "rivet", limit: nil))
    #expect(after.hits.map(\.path) == before.hits.map(\.path))
}

@Test("rebuild reconciles the index to the files, not trusting stale entries (AC-48.3)")
func rebuildReconcilesStaleIndex() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = InMemoryNoteSearchIndex()
    let service = MarkdownKnowledgeService(rootURL: root, searchIndex: index, clock: FixedClock(t0, step: 1))

    // A real note on disk, indexed at capture.
    _ = try await service.capture(NoteCaptureRequest(title: "Captured note", body: "real hull", kind: "note", project: nil, sensitivity: nil))
    // A stale/phantom entry as if restored from an untrusted index — no file backs it.
    try index.upsert(NoteSearchIndexEntry(noteID: "ghost", path: "inbox/ghost.md", title: "ghost", body: "real phantom", sensitivity: nil, updated: nil, reviewAfter: nil))
    #expect(try await service.search(NoteSearchRequest(query: "real", limit: nil)).hits.count == 2)

    // After a restore the derived index is rebuilt from the durable files, so the
    // phantom disappears and only on-disk notes remain (FR-UPD-07).
    try service.rebuild()
    let hits = try await service.search(NoteSearchRequest(query: "real", limit: nil)).hits
    #expect(hits.count == 1)
    #expect(hits.allSatisfy { $0.noteID != "ghost" })
}

@Test("freshness is derived from the review boundary")
func freshnessFromReviewBoundary() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let index = InMemoryNoteSearchIndex()
    try index.upsert(NoteSearchIndexEntry(noteID: "past", path: "inbox/past.md", title: "p", body: "due", sensitivity: nil, updated: t0, reviewAfter: t0))
    try index.upsert(NoteSearchIndexEntry(noteID: "future", path: "inbox/future.md", title: "f", body: "due", sensitivity: nil, updated: t0, reviewAfter: t0.addingTimeInterval(3600)))
    try index.upsert(NoteSearchIndexEntry(noteID: "none", path: "inbox/none.md", title: "n", body: "due", sensitivity: nil, updated: t0, reviewAfter: nil))
    // Clock sits between the past and future review boundaries.
    let service = MarkdownKnowledgeService(rootURL: root, searchIndex: index, clock: FixedClock(t0.addingTimeInterval(60)))

    let hits = try await service.search(NoteSearchRequest(query: "due", limit: nil)).hits
    let freshnessByID = Dictionary(uniqueKeysWithValues: hits.map { ($0.noteID, $0.freshness) })
    #expect(freshnessByID["past"] == "stale")
    #expect(freshnessByID["future"] == "fresh")
    #expect(freshnessByID["none"] == "unknown")
}
