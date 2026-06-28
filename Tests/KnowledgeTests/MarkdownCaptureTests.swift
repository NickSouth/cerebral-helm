import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared
@testable import CerebralKnowledge

/// NIC-44 (PRE-DATA-2): atomic Markdown note capture (FR-KNW-02, NFR-06).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-knowledge-\(UUID().uuidString)", isDirectory: true)
}

private func fileURL(for relativePath: String, under root: URL) -> URL {
    relativePath.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
}

@Test("capture writes a complete Markdown note and records its metadata")
func captureWritesNoteAndMetadata() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InMemoryNoteMetadataStore()
    let service = MarkdownKnowledgeService(rootURL: root, metadataStore: store, clock: FixedClock(t0))

    let outcome = try await service.capture(
        NoteCaptureRequest(title: "Captured note", body: "deploy at 5pm", kind: "note", project: nil, sensitivity: nil)
    )

    #expect(outcome.created)
    #expect(outcome.path.hasPrefix("inbox/"))
    #expect(outcome.path.hasSuffix(".md"))

    // The Markdown source exists (AC-44.2) and is complete and parseable — evidence
    // the atomic write produced the whole note, never a partial one (AC-44.1).
    let url = fileURL(for: outcome.path, under: root)
    #expect(FileManager.default.fileExists(atPath: url.path))
    let (frontmatter, body) = FrontmatterCodec.parse(try String(contentsOf: url, encoding: .utf8))
    #expect(frontmatter["id"] == outcome.noteID)
    #expect(frontmatter["sensitivity"] == "private")  // safe default
    #expect(frontmatter["cloudPolicy"] == "deny")      // never allow by default
    #expect(body.contains("deploy at 5pm"))

    // Rebuildable metadata row recorded.
    let entry = try store.get(noteID: outcome.noteID)
    #expect(entry?.path == outcome.path)
    #expect(entry?.cloudPolicy == "deny")
}

@Test("a note with a project lands under projects/<project>/")
func captureRoutesByProject() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = MarkdownKnowledgeService(rootURL: root, metadataStore: nil, clock: FixedClock(t0))

    let outcome = try await service.capture(
        NoteCaptureRequest(title: "Plan", body: "x", kind: "project-note", project: "cerebralhelm", sensitivity: nil)
    )
    #expect(outcome.path.hasPrefix("projects/cerebralhelm/"))
}

@Test("capturing a colliding id throws and never overwrites the existing note (AC-44.3)")
func captureCollisionNeverOverwrites() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    // A frozen clock yields the same capture id, forcing a collision.
    let service = MarkdownKnowledgeService(rootURL: root, metadataStore: nil, clock: FixedClock(t0))

    let first = try await service.capture(
        NoteCaptureRequest(title: "Captured note", body: "original", kind: "note", project: nil, sensitivity: nil)
    )
    do {
        _ = try await service.capture(
            NoteCaptureRequest(title: "Captured note", body: "overwrite attempt", kind: "note", project: nil, sensitivity: nil)
        )
        Issue.record("expected a collision error")
    } catch let error as KnowledgeServiceError {
        guard case .collision = error else {
            Issue.record("expected collision, got \(error)")
            return
        }
    }

    let content = try String(contentsOf: fileURL(for: first.path, under: root), encoding: .utf8)
    #expect(content.contains("original"))
    #expect(!content.contains("overwrite attempt"))
}

@Test("filesystem errors map to structured knowledge errors (AC-44.3)")
func classifyMapsFilesystemErrors() {
    #expect(
        MarkdownKnowledgeService.classify(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue))
            == .rootReadOnly
    )
    #expect(
        MarkdownKnowledgeService.classify(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue))
            == .rootUnavailable
    )
    if case .writeFailed = MarkdownKnowledgeService.classify(NSError(domain: "Other", code: 1)) {
        // expected
    } else {
        Issue.record("expected writeFailed for an unclassified error")
    }
}

@Test("a captured note is findable by content")
func captureThenSearchFinds() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = MarkdownKnowledgeService(
        rootURL: root, metadataStore: nil, searchIndex: InMemoryNoteSearchIndex(), clock: FixedClock(t0)
    )

    _ = try await service.capture(
        NoteCaptureRequest(title: "Captured note", body: "rivet the hull", kind: "note", project: nil, sensitivity: nil)
    )
    let result = try await service.search(NoteSearchRequest(query: "rivet", limit: nil))

    #expect(result.hits.count == 1)
    #expect(result.hits.first?.path.hasSuffix(".md") == true)
    #expect(result.hits.first?.sensitivity == "private")
}

@Test("a capture into an unusable root fails with recovery guidance and discards nothing (AC-49.1, AC-49.3)")
func captureIntoUnusableRootIsStructured() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // Use an existing *file* as the "root", so creating subdirectories under it fails.
    let fileAsRoot = root.appendingPathComponent("not-a-directory")
    try Data("user data".utf8).write(to: fileAsRoot)
    let service = MarkdownKnowledgeService(rootURL: fileAsRoot, clock: FixedClock(t0))

    do {
        _ = try await service.capture(
            NoteCaptureRequest(title: "Captured note", body: "y", kind: "note", project: nil, sensitivity: nil)
        )
        Issue.record("expected capture into an unusable root to fail")
    } catch let error as KnowledgeServiceError {
        let diagnostic = RecoveryDiagnostic.forKnowledge(error)
        #expect(diagnostic.store == "knowledge")
        #expect(!diagnostic.guidance.isEmpty) // failures map to recovery guidance (AC-49.1)
    }

    // The user's existing file is untouched — nothing is silently discarded (AC-49.3).
    #expect(try String(contentsOf: fileAsRoot, encoding: .utf8) == "user data")
}

@Test("the frontmatter codec round-trips metadata and body")
func codecRoundTrips() {
    let metadata = NoteMetadataNormalizer.normalize(
        NoteDraft(id: "ship-the-helm", title: "Ship the Helm", kind: "project-note", project: "cerebralhelm"),
        now: t0
    )
    let (frontmatter, body) = FrontmatterCodec.parse(FrontmatterCodec.emit(metadata: metadata, body: "Line one\nLine two"))

    #expect(frontmatter["id"] == "ship-the-helm")
    #expect(frontmatter["title"] == "Ship the Helm")
    #expect(frontmatter["project"] == "cerebralhelm")
    #expect(frontmatter["cloudPolicy"] == "deny")
    #expect(body.contains("Line one"))
    #expect(body.contains("Line two"))
}
