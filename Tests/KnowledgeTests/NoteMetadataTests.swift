import Foundation
import Testing

import CerebralContracts
import CerebralKnowledge

/// NIC-43 (PRE-DATA-1): note metadata rules and safe defaults (FR-KNW-05).

private let now = Date(timeIntervalSince1970: 1_700_000_000)

@Test("absent optional metadata degrades to safe defaults; cloud policy never defaults to allow (AC-43.3)")
func safeDefaultsApplied() {
    let metadata = NoteMetadataNormalizer.normalize(NoteDraft(title: "Quick thought", kind: "note"), now: now)

    #expect(metadata.cloudPolicy == .deny)
    #expect(metadata.cloudPolicy != .allow) // the absence of a policy never grants cloud access
    #expect(metadata.sensitivity == .sensitivityPrivate)
    #expect(metadata.status == .active)
    #expect(metadata.schemaVersion == "1.0.0")
    #expect(metadata.created == now)
    #expect(metadata.updated == now)
    #expect(metadata.id == "quick-thought")
    #expect(metadata.project == nil)
    #expect(metadata.reviewAfter == nil)
}

@Test("explicit metadata is preserved, including an explicit cloud policy")
func explicitValuesPreserved() {
    let draft = NoteDraft(
        id: "custom-id", title: "Secret plan", kind: "project-note", project: "cerebralhelm",
        sensitivity: .secret, cloudPolicy: .ask, status: .draft, reviewAfter: now
    )
    let metadata = NoteMetadataNormalizer.normalize(draft, now: now.addingTimeInterval(10))

    #expect(metadata.id == "custom-id") // a provided id is not re-slugged
    #expect(metadata.project == "cerebralhelm")
    #expect(metadata.sensitivity == .secret)
    #expect(metadata.cloudPolicy == .ask)
    #expect(metadata.status == .draft)
    #expect(metadata.reviewAfter == now)
    #expect(metadata.created == now.addingTimeInterval(10))
}

@Test("normalized metadata is contract-valid (round-trips through the schema DTO)")
func normalizedRoundTripsThroughContract() throws {
    let metadata = NoteMetadataNormalizer.normalize(NoteDraft(title: "Ship the Helm", kind: "project-note"), now: now)
    let decoded = try CerebralHelmNoteMetadata(data: metadata.jsonData())

    #expect(decoded.id == "ship-the-helm")
    #expect(decoded.cloudPolicy == .deny)
    #expect(decoded.sensitivity == .sensitivityPrivate)
    #expect(decoded.schemaVersion == "1.0.0")
}

@Test("ids are derived as file-safe slugs of the title (FR-KNW-02)")
func namingSlugifies() {
    #expect(NoteNaming.id(fromTitle: "Ship the Helm!") == "ship-the-helm")
    #expect(NoteNaming.id(fromTitle: "  Multiple   spaces  ") == "multiple-spaces")
    #expect(NoteNaming.id(fromTitle: "Q4 2026 — Plan") == "q4-2026-plan")
    #expect(NoteNaming.id(fromTitle: "????") == "note") // no usable characters → safe fallback
    #expect(NoteNaming.filename(forID: "ship-the-helm") == "ship-the-helm.md")
}
