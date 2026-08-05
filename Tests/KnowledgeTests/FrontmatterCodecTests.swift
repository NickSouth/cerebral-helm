// NIC-116: real YAML on the frontmatter read path; the hand-rolled emitter still writes.
import Foundation
import Testing

import CerebralContracts
import CerebralKnowledge
import CerebralShared

private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

private func note(_ frontmatter: String, body: String = "The body.") -> String {
    "---\n\(frontmatter)\n---\n\n\(body)\n"
}

// MARK: - The defect this ticket exists for

@Test("a tag list is read, not silently dropped (NIC-116)")
func readsSequenceValues() {
    // The old line-splitting parser required a colon per line, so `- work` and `- urgent` were
    // skipped entirely and `tags` came back as "". Obsidian writes tags exactly like this, so any
    // note authored outside CerebralHelm lost them on read.
    let (frontmatter, _) = FrontmatterCodec.parse(note("""
    title: Weekly review
    tags:
      - work
      - urgent
    """))

    #expect(frontmatter["title"] == "Weekly review")
    #expect(frontmatter["tags"] == "work, urgent")
}

@Test("an inline sequence reads the same as a block one")
func readsInlineSequence() {
    let (frontmatter, _) = FrontmatterCodec.parse(note("tags: [work, urgent]"))
    #expect(frontmatter["tags"] == "work, urgent")
}

@Test("a nested mapping is reachable under dotted keys rather than discarded")
func flattensNestedMapping() {
    let (frontmatter, _) = FrontmatterCodec.parse(note("""
    author:
      name: Nick
      handle: nsouthey
    """))

    #expect(frontmatter["author.name"] == "Nick")
    #expect(frontmatter["author.handle"] == "nsouthey")
}

// MARK: - Scalar fidelity (why `compose` and not `load`)

@Test("scalars keep their literal text — no implicit type coercion")
func preservesScalarText() {
    // `Yams.load` would resolve these before we saw them: a Date, the integer 7, and false.
    // Each loses what the author actually typed on the way into a String map, so the node tree's
    // verbatim scalar text is used instead.
    let (frontmatter, _) = FrontmatterCodec.parse(note("""
    created: 2026-08-05
    id: 007
    draft: no
    ratio: 1.50
    """))

    #expect(frontmatter["created"] == "2026-08-05")
    #expect(frontmatter["id"] == "007")
    #expect(frontmatter["draft"] == "no")
    #expect(frontmatter["ratio"] == "1.50")
}

@Test("a quoted value containing a colon survives intact")
func handlesQuotedColons() {
    // The old parser split on the FIRST colon, so this title was truncated to "Meeting".
    let (frontmatter, _) = FrontmatterCodec.parse(note(#"title: "Meeting: Q3 planning""#))
    #expect(frontmatter["title"] == "Meeting: Q3 planning")
}

@Test("block scalars are read as one value")
func handlesBlockScalars() {
    let (frontmatter, _) = FrontmatterCodec.parse(note("""
    summary: |
      First line.
      Second line.
    folded: >
      One
      logical line.
    """))

    // Literal (`|`) keeps its internal line breaks; folded (`>`) joins them into one line. The
    // trailing newline differs only because `folded` is the last node in the block, so clip
    // chomping has no final break to keep — standard YAML, not a quirk of this codec.
    #expect(frontmatter["summary"] == "First line.\nSecond line.\n")
    #expect(frontmatter["folded"] == "One logical line.")
}

@Test("an empty value reads as the empty string, as it did before")
func nullReadsAsEmpty() {
    let (frontmatter, _) = FrontmatterCodec.parse(note("project:\ntitle: Untitled"))
    #expect(frontmatter["project"] == "")
    #expect(frontmatter["title"] == "Untitled")
}

// MARK: - Degradation (a half-edited note must stay readable)

@Test("malformed YAML yields no frontmatter but keeps the body")
func malformedYamlDegrades() {
    // Mid-edit, a note can hold YAML that does not parse. Its body is the valuable part, so this
    // must not throw and must not swallow the content.
    let (frontmatter, body) = FrontmatterCodec.parse(note("title: [unclosed\n  bad: : :", body: "Still here."))
    #expect(frontmatter.isEmpty)
    #expect(body.contains("Still here."))
}

@Test("a block that is not a mapping is not frontmatter")
func nonMappingBlockDegrades() {
    let (frontmatter, body) = FrontmatterCodec.parse(note("- just\n- a list", body: "Body text."))
    #expect(frontmatter.isEmpty)
    #expect(body.contains("Body text."))
}

@Test("a document with no frontmatter block is all body")
func noBlockIsAllBody() {
    let markdown = "# Heading\n\nSome prose.\n"
    let (frontmatter, body) = FrontmatterCodec.parse(markdown)
    #expect(frontmatter.isEmpty)
    #expect(body == markdown)
}

@Test("an unterminated block is all body, never a partial read")
func unterminatedBlockIsAllBody() {
    let markdown = "---\ntitle: Never closed\n\nSome prose.\n"
    let (frontmatter, body) = FrontmatterCodec.parse(markdown)
    #expect(frontmatter.isEmpty)
    #expect(body == markdown)
}

// MARK: - The two halves must not drift

@Test("everything the emitter writes is read back identically (round-trip guard)")
func emitParseRoundTripsExactly() {
    // The codec is deliberately asymmetric — Yams reads, the hand-rolled emitter writes — so this
    // is the guard that keeps them agreeing. Values are chosen to exercise the emitter's escaping
    // and the reader's scalar handling together: quotes, backslashes, a colon, and an ISO stamp.
    let metadata = NoteMetadataNormalizer.normalize(
        NoteDraft(
            id: "ship-the-helm",
            title: #"Ship the "Helm": v1 \ final"#,
            kind: "project-note",
            project: "cerebralhelm"
        ),
        now: t0
    )
    let emitted = FrontmatterCodec.emit(metadata: metadata, body: "Line one\nLine two")
    let (frontmatter, body) = FrontmatterCodec.parse(emitted)

    #expect(frontmatter["id"] == metadata.id)
    #expect(frontmatter["title"] == metadata.title)
    #expect(frontmatter["project"] == metadata.project)
    #expect(frontmatter["kind"] == metadata.kind)
    #expect(frontmatter["sensitivity"] == metadata.sensitivity.rawValue)
    #expect(frontmatter["cloudPolicy"] == metadata.cloudPolicy.rawValue)
    #expect(frontmatter["status"] == metadata.status.rawValue)
    #expect(frontmatter["schemaVersion"] == metadata.schemaVersion)
    // Timestamps must come back as the ISO text that was written, not a re-formatted date.
    #expect(frontmatter["created"] == ISO8601Timestamp.string(from: metadata.created))
    #expect(frontmatter["updated"] == ISO8601Timestamp.string(from: metadata.updated))
    #expect(body == "Line one\nLine two\n")
}

@Test("a note written by the emitter and edited by hand still reads")
func emittedNoteToleratesHandEditing() {
    // The realistic lifecycle: CerebralHelm captures a note, the user opens it in Obsidian and adds
    // a tag list. Both halves have to survive the next read.
    let metadata = NoteMetadataNormalizer.normalize(
        NoteDraft(id: "hand-edited", title: "Hand edited", kind: "note", project: nil), now: t0
    )
    let emitted = FrontmatterCodec.emit(metadata: metadata, body: "Original body.")
    let edited = emitted.replacingOccurrences(
        of: "\n---\n", with: "\ntags:\n  - added\n  - later\n---\n"
    )

    let (frontmatter, body) = FrontmatterCodec.parse(edited)
    #expect(frontmatter["id"] == "hand-edited")
    #expect(frontmatter["tags"] == "added, later")
    #expect(body.contains("Original body."))
}
