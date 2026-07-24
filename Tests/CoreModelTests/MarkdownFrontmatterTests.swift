import Foundation
import Testing

import CerebralShared

/// NIC-129 Increment 1: a minimal, parse-only frontmatter reader in the shared package (a
/// `CerebralCore`-importable sibling of the knowledge module's `FrontmatterCodec`). It backs
/// the Projects widget's `importance` ordering.

@Test("parses a flat frontmatter block and returns the body after it")
func parsesFrontmatterAndBody() {
    let (frontmatter, body) = MarkdownFrontmatter.parse(
        """
        ---
        importance: 10
        title: "Cerebral Helm"
        ---
        # Heading

        Body text.
        """
    )
    #expect(frontmatter["importance"] == "10")
    #expect(frontmatter["title"] == "Cerebral Helm") // matching quotes are stripped
    #expect(body == "# Heading\n\nBody text.")
}

@Test("a document with no leading --- is all body, with an empty map")
func noFrontmatterIsAllBody() {
    let markdown = "# Just a heading\n\nNo frontmatter here."
    let (frontmatter, body) = MarkdownFrontmatter.parse(markdown)
    #expect(frontmatter.isEmpty)
    #expect(body == markdown)
}

@Test("an unterminated frontmatter block is treated as body, not parsed")
func unterminatedBlockIsBody() {
    let markdown = "---\nimportance: 3\nstill going"
    let (frontmatter, body) = MarkdownFrontmatter.parse(markdown)
    #expect(frontmatter.isEmpty)
    #expect(body == markdown)
}

@Test("lines without a colon (e.g. comments) are skipped")
func skipsLinesWithoutColon() {
    let (frontmatter, _) = MarkdownFrontmatter.parse(
        """
        ---
        # a comment
        importance: 5
        ---
        Body.
        """
    )
    #expect(frontmatter == ["importance": "5"])
}

@Test("an empty frontmatter block yields an empty map and the body")
func emptyFrontmatterBlock() {
    let (frontmatter, body) = MarkdownFrontmatter.parse("---\n---\nBody only.")
    #expect(frontmatter.isEmpty)
    #expect(body == "Body only.")
}
