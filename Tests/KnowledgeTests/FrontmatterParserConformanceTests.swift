// NIC-116: the two frontmatter readers must agree on the grammar they share.
import Foundation
import Testing

import CerebralKnowledge
import CerebralShared

/// The repository has **two** frontmatter readers, deliberately:
///
/// - ``FrontmatterCodec`` in `CerebralKnowledge` — Yams-backed, full YAML. It reads user-authored
///   vault notes, which really do contain tag lists, nested mappings and block scalars.
/// - ``MarkdownFrontmatter`` in `CerebralShared` — narrow, dependency-free. It reads `PROJECT.md`
///   descriptors, whose frontmatter is a single flat scalar (`importance: 5`) written by
///   CerebralHelm's own scaffolder and by the shipped hand-authoring template.
///
/// They are not merged because `CerebralCore` cannot import `CerebralKnowledge` (siblings), and the
/// obvious fix — moving the Yams-backed parser down into `CerebralShared` — would pull a C-backed
/// YAML parser into *every* package's dependency graph (Core, Tools, Storage, Contracts) to serve
/// one integer key. `RepositoryBoundaryTests` enforces that confinement.
///
/// The cost of that choice is drift: two parsers, one grammar in common. These tests are what stops
/// it. Every case below is the **flat-scalar grammar both must support identically** — if someone
/// changes either reader in a way that diverges on this shared subset, this fails.
///
/// Cases where they legitimately differ (sequences, nested mappings, block scalars, malformed YAML)
/// are deliberately NOT asserted here — those are `FrontmatterCodec`'s job alone, covered in
/// `FrontmatterCodecTests`, and `MarkdownFrontmatter` is documented as not supporting them.
private let sharedGrammarCases: [(name: String, markdown: String)] = [
    ("a single scalar", "---\nimportance: 5\n---\n\n# Project\n"),
    ("several scalars", "---\nimportance: 3\nowner: nick\nstatus: active\n---\n\nBody.\n"),
    ("a quoted value", "---\ntitle: \"Quarterly planning\"\n---\n\nBody.\n"),
    ("an empty value", "---\nimportance:\n---\n\nBody.\n"),
    ("no frontmatter block at all", "# Just a heading\n\nProse.\n"),
    ("an unterminated block", "---\nimportance: 5\n\nProse.\n"),
    ("an empty document", ""),
    ("a body containing a --- rule", "---\nimportance: 5\n---\n\nIntro.\n\n---\n\nAfter the rule.\n"),
    ("CRLF-free multi-paragraph body", "---\nimportance: 1\n---\n\nOne.\n\nTwo.\n\nThree.\n")
]

@Test("both frontmatter readers agree on the flat-scalar grammar they share (NIC-116)")
func readersAgreeOnSharedGrammar() {
    for testCase in sharedGrammarCases {
        let yaml = FrontmatterCodec.parse(testCase.markdown)
        let narrow = MarkdownFrontmatter.parse(testCase.markdown)

        #expect(
            yaml.frontmatter == narrow.frontmatter,
            "frontmatter differs for \(testCase.name): \(yaml.frontmatter) vs \(narrow.frontmatter)"
        )
        #expect(
            yaml.body == narrow.body,
            "body differs for \(testCase.name)"
        )
    }
}

@Test("both readers read the descriptor shape CerebralHelm actually writes")
func readersAgreeOnRealDescriptor() {
    // The exact bytes `ProjectScaffolder.descriptorContents` produces — the only `PROJECT.md`
    // frontmatter shape in circulation. If either reader stops handling this, project importance
    // silently reverts to its default and the Projects panel reorders itself.
    let descriptor = """
    ---
    importance: 7
    ---

    # Cerebral Helm

    _One-line summary of what this project is._

    ## Focus

    - First priority
    """

    let yaml = FrontmatterCodec.parse(descriptor)
    let narrow = MarkdownFrontmatter.parse(descriptor)

    #expect(narrow.frontmatter["importance"] == "7")
    #expect(yaml.frontmatter == narrow.frontmatter)
    #expect(yaml.body == narrow.body)
    #expect(yaml.body.hasPrefix("# Cerebral Helm"))
}
