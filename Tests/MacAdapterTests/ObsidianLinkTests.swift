import Foundation
import Testing

import CerebralMacAdapters

/// NIC-162: the Obsidian hand-off for browsing durable notes.

@Test("the knowledge root becomes an obsidian://open link carrying the whole path")
func openURLEncodesTheRoot() throws {
    let url = try #require(ObsidianLink.openURL(forRoot: URL(fileURLWithPath: "/Users/me/knowledge")))

    #expect(url.scheme == "obsidian")
    #expect(url.absoluteString.hasPrefix("obsidian://open?path="))
    // Path separators are percent-encoded, per the URI documentation.
    #expect(url.absoluteString == "obsidian://open?path=%2FUsers%2Fme%2Fknowledge")
}

@Test("a path with spaces, delimiters, or non-ASCII survives as one parameter value")
func openURLEscapesReservedCharacters() throws {
    for path in [
        "/Users/me/My Knowledge",
        "/Users/me/notes & ideas",
        "/Users/me/notes#1",
        "/Users/me/notes?draft",
        "/Users/me/知識"
    ] {
        let url = try #require(ObsidianLink.openURL(forRoot: URL(fileURLWithPath: path)))
        let encoded = String(url.absoluteString.dropFirst("obsidian://open?path=".count))

        // Nothing may survive raw that would end the parameter early or split it.
        #expect(!encoded.contains(" "))
        #expect(!encoded.contains("&"))
        #expect(!encoded.contains("#"))
        #expect(!encoded.contains("?"))
        // And it must decode back to exactly the path we meant to hand over.
        #expect(encoded.removingPercentEncoding == path)
    }
}

@Test("without Obsidian installed, a browse request reveals the folder instead")
func destinationFallsBackToFinder() {
    let root = URL(fileURLWithPath: "/Users/me/knowledge")

    #expect(
        ObsidianLink.destination(forRoot: root, obsidianInstalled: false) == .revealInFinder(root)
    )
    // Installed: the request goes to Obsidian, never to Finder as well.
    guard case let .obsidian(url) = ObsidianLink.destination(forRoot: root, obsidianInstalled: true) else {
        Issue.record("an installed Obsidian must take the browse request")
        return
    }
    #expect(url == ObsidianLink.openURL(forRoot: root))
}
