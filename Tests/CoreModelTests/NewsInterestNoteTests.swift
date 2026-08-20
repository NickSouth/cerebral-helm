import Foundation
import Testing

import CerebralCore

/// NIC-223: the user's "News Interests" note, parsed from Markdown in the knowledge vault. A `##`
/// heading names a mode, the bullets under it are that mode's search terms, and `## Any mode` is
/// shared by every profile. Parsing is total — every malformed shape degrades to fewer interests,
/// never to an error.

private let newsInterestsMarkdown = """
---
schemaVersion: "1.0.0"
id: news-interests
title: News Interests
kind: reference
---

# News Interests

Prose above the first mode heading is ignored.

- this bullet sits under no mode heading and is ignored

## Executive

- **artificial intelligence** — the industry I work in
- **"interest rates"** — affects the mortgage
- **mergers**

## Developer

- `Swift` — my main language
- [[open-source|open source]] – tooling I depend on
  - a nested note about open source, not a term of its own

### Not a mode

- this sits under a sub-heading and is elaboration, not a term

## Any mode

- **New Zealand** - home

## Gardening

- compost — no mode is called Gardening, so this is ignored
"""

private let newsInterestsModeProfiles = [
    "executive": "broad",
    "developer": "engineering",
    "school": "academic",
    "entertainment": "interest",
]

@Test("a `##` heading names a mode section and its bullets become that mode's interests")
func newsInterestsParsesModeSections() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    #expect(note.sections["executive"]?.map(\.term) == ["artificial intelligence", "interest rates", "mergers"])
    #expect(note.sections["developer"]?.map(\.term) == ["Swift", "open source"])
    #expect(note.sections["any mode"]?.map(\.term) == ["New Zealand"])
}

@Test("frontmatter, prose, and bullets before the first mode heading contribute nothing")
func newsInterestsIgnoresEverythingOutsideASection() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    // The frontmatter's `title:`/`kind:` lines and the stray leading bullet would both be terms if
    // the note were read as one flat list.
    #expect(note.sections.keys.sorted() == ["any mode", "developer", "executive", "gardening"])
}

@Test("all three term/context separators split an item, and an item may carry no context")
func newsInterestsSplitsTermFromContext() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    let executive = note.sections["executive"]
    #expect(executive?.first?.context == "the industry I work in")           // em dash
    #expect(note.sections["developer"]?.last?.context == "tooling I depend on")  // en dash
    #expect(note.sections["any mode"]?.first?.context == "home")             // spaced hyphen
    #expect(executive?.last?.term == "mergers")
    #expect(executive?.last?.context == nil)
}

@Test("emphasis, backticks, and wikilinks decorate a term without becoming part of it")
func newsInterestsStripsInlineMarkup() {
    let note = NewsInterestNote.parse("""
    ## Executive

    - **bold** — a
    - `code` — b
    - [[a-note|aliased]] — c
    - [[bare-note]] — d
    - *italic* — e
    - [linked](https://example.com) — f
    - snake_case_term — g
    """)
    #expect(note.sections["executive"]?.map(\.term) == [
        "bold", "code", "aliased", "bare-note", "italic", "linked", "snake_case_term",
    ])
}

@Test("a quoted or multi-word term matches as a phrase; a bare single word does not")
func newsInterestsMarksPhrases() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    let executive = note.sections["executive"]
    #expect(executive?[0].isPhrase == true)   // multi-word, unquoted
    #expect(executive?[1].term == "interest rates")
    #expect(executive?[1].isPhrase == true)   // quoted, and the quotes are not part of the term
    #expect(executive?[2].isPhrase == false)  // single bare word
}

@Test("a nested bullet is elaboration, and a `###` sub-heading ends the mode section")
func newsInterestsIgnoresNestedItemsAndSubheadings() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    #expect(note.sections["developer"]?.count == 2)
    #expect(note.sections["not a mode"] == nil)
}

@Test("a fenced example inside the note does not inject its own sample terms")
func newsInterestsIgnoresFencedBlocks() {
    let note = NewsInterestNote.parse("""
    ## Executive

    - real term — kept

    ```markdown
    - sample term — an example of the layout, not an interest
    ```

    - second real term — also kept
    """)
    #expect(note.sections["executive"]?.map(\.term) == ["real term", "second real term"])
}

@Test("headings resolve to profiles by mode id or label, case-insensitively")
func newsInterestsResolvesHeadingsToProfiles() {
    let note = NewsInterestNote.parse("""
    ## EXECUTIVE

    - alpha — by id, shouting

    ## Developer

    - beta — by label, title case
    """)
    let resolved = note.resolve(modeProfiles: newsInterestsModeProfiles)
    #expect(resolved["broad"]?.map(\.term) == ["alpha"])
    #expect(resolved["engineering"]?.map(\.term) == ["beta"])
}

@Test("the shared section is appended to every profile, after that mode's own terms")
func newsInterestsMergesSharedSection() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    let resolved = note.resolve(modeProfiles: newsInterestsModeProfiles)
    // Mode-specific terms lead: the note's order is its priority order.
    #expect(resolved["broad"]?.map(\.term) == [
        "artificial intelligence", "interest rates", "mergers", "New Zealand",
    ])
    // A mode with no section of its own still gets the shared terms.
    #expect(resolved["academic"]?.map(\.term) == ["New Zealand"])
    #expect(resolved["interest"]?.map(\.term) == ["New Zealand"])
}

@Test("two modes sharing one profile have their terms unioned, first occurrence winning")
func newsInterestsUnionsModesSharingAProfile() {
    let note = NewsInterestNote.parse("""
    ## Executive

    - alpha — from executive
    - shared — first occurrence wins

    ## School

    - beta — from school
    - SHARED — dropped as a duplicate
    """)
    let resolved = note.resolve(modeProfiles: ["executive": "broad", "school": "broad"])
    #expect(resolved["broad"]?.map(\.term) == ["alpha", "shared", "beta"])
    #expect(resolved["broad"]?.first(where: { $0.term == "shared" })?.context == "first occurrence wins")
}

@Test("a heading matching no mode is ignored rather than treated as a fault")
func newsInterestsIgnoresUnknownHeadings() {
    let note = NewsInterestNote.parse(newsInterestsMarkdown)
    #expect(note.sections["gardening"] != nil)
    let resolved = note.resolve(modeProfiles: newsInterestsModeProfiles)
    #expect(resolved.values.flatMap { $0 }.contains { $0.term == "compost" } == false)
}

@Test("an empty or frontmatter-only note resolves to no interests, not an error")
func newsInterestsHandlesEmptyNotes() {
    #expect(NewsInterestNote.parse("").sections.isEmpty)
    #expect(NewsInterestNote.parse("---\ntitle: News Interests\n---\n").sections.isEmpty)
    // Unterminated frontmatter is malformed, not a body: its `title:` line must not become prose.
    #expect(NewsInterestNote.parse("---\ntitle: News Interests\n").sections.isEmpty)
    #expect(NewsInterestNote.parse(newsInterestsMarkdown).resolve(modeProfiles: [:]).isEmpty)
}

@Test("load finds the note at its documented path, or anywhere in the vault, and nil when absent")
func newsInterestsLoadsFromTheKnowledgeRoot() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("news-interests-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Nothing in the vault → nil, so the caller degrades to the pre-NIC-223 behaviour.
    #expect(NewsInterestNote.load(knowledgeRoot: root) == nil)

    // Filed somewhere else by a triage pass: found by filename, not by folder.
    let archive = root.appendingPathComponent("archive", isDirectory: true)
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    try "## Executive\n\n- moved — found by filename".write(
        to: archive.appendingPathComponent(NewsInterestNote.filename), atomically: true, encoding: .utf8
    )
    #expect(NewsInterestNote.load(knowledgeRoot: root)?.sections["executive"]?.first?.term == "moved")

    // The documented location wins once the note is filed there.
    let reference = root.appendingPathComponent("reference", isDirectory: true)
    try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: true)
    try "## Executive\n\n- preferred — the documented home".write(
        to: reference.appendingPathComponent(NewsInterestNote.filename), atomically: true, encoding: .utf8
    )
    #expect(NewsInterestNote.load(knowledgeRoot: root)?.sections["executive"]?.first?.term == "preferred")
}

@Test("a knowledge root that does not exist is nil, never a crash")
func newsInterestsLoadsNothingFromAMissingRoot() {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("news-interests-absent-\(UUID().uuidString)", isDirectory: true)
    #expect(NewsInterestNote.load(knowledgeRoot: missing) == nil)
}
