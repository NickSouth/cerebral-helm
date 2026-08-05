// The free RSS/Atom fallback behind the metered news provider (the news quota fix, increment 2).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

/// Both dialects are exercised because real publishers ship both: BBC and NPR are RSS `<item>`
/// with CDATA titles and text `<link>`s; The Verge is Atom `<entry>` with an `href` attribute and
/// no link text at all. A feed silently yielding nothing because of its dialect would be an
/// invisible failure, so the shapes below are copied from those live feeds.

private let rssFeed = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>BBC News</title>
    <link>https://www.bbc.co.uk/news</link>
    <item>
      <title><![CDATA[Apple issues new challenge against UK order]]></title>
      <description><![CDATA[The latest development in the dispute.]]></description>
      <link>https://www.bbc.co.uk/news/articles/abc123</link>
      <guid isPermaLink="false">https://www.bbc.co.uk/news/articles/abc123#0</guid>
    </item>
    <item>
      <title>Rates held steady</title>
      <link>https://www.bbc.co.uk/news/articles/def456</link>
      <guid isPermaLink="false">bbc-def456</guid>
    </item>
    <item>
      <title></title>
      <link>https://www.bbc.co.uk/news/articles/blank</link>
      <guid>bbc-blank</guid>
    </item>
  </channel>
</rss>
"""

private let atomFeed = """
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>The Verge</title>
  <id>https://www.theverge.com/rss/index.xml</id>
  <entry>
    <author><name>Cameron Faulkner</name></author>
    <title type="html"><![CDATA[A back-to-school bag of free tech]]></title>
    <link rel="alternate" type="text/html" href="https://www.theverge.com/gadgets/972547/back-to-school" />
    <id>https://www.theverge.com/?p=972547</id>
  </entry>
</feed>
"""

@Test("an RSS feed parses CDATA titles, text links and guids, and takes the channel as the source")
func rssParsesRSSDialect() throws {
    let items = try RSSNewsProvider.parse(Data(rssFeed.utf8), source: nil, fallbackSource: "fallback.example")

    #expect(items.count == 2, "the item with a blank title is skipped, never rendered empty")
    #expect(items[0].title == "Apple issues new challenge against UK order")
    #expect(items[0].source == "BBC News", "the channel title, not the item-level or feed URL")
    #expect(items[0].url == "https://www.bbc.co.uk/news/articles/abc123")
    #expect(items[0].id == "https://www.bbc.co.uk/news/articles/abc123#0", "the feed's own guid")
    #expect(items[1].title == "Rates held steady")
}

@Test("an Atom feed parses entry titles and the link href, never the feed-level id")
func rssParsesAtomDialect() throws {
    let items = try RSSNewsProvider.parse(Data(atomFeed.utf8), source: nil, fallbackSource: "fallback.example")

    #expect(items.count == 1)
    #expect(items[0].title == "A back-to-school bag of free tech")
    #expect(items[0].source == "The Verge")
    #expect(items[0].url == "https://www.theverge.com/gadgets/972547/back-to-school", "the href attribute")
    #expect(items[0].id == "https://www.theverge.com/?p=972547", "the entry id, not the feed id")
}

@Test("a feed with no channel title falls back to the feed's host, never a fabricated name")
func rssFallsBackToHostAsSource() throws {
    let feed = """
    <rss version="2.0"><channel>
      <item><title>Something happened</title><link>https://ex.com/a</link></item>
    </channel></rss>
    """
    let items = try RSSNewsProvider.parse(Data(feed.utf8), source: nil, fallbackSource: "ex.com")
    #expect(items[0].source == "ex.com")
}

@Test("an item with no link is kept but has no url — non-interactive, never fabricated")
func rssItemWithoutLinkHasNoURL() throws {
    let feed = """
    <rss version="2.0"><channel><title>Wire</title>
      <item><title>Unlinked story</title></item>
    </channel></rss>
    """
    let items = try RSSNewsProvider.parse(Data(feed.utf8), source: nil, fallbackSource: "ex.com")
    #expect(items.count == 1)
    #expect(items[0].url == nil)
    #expect(items[0].id == "feed:Wire:Unlinked story", "a title-derived key, so it is never dropped")
}

@Test("a non-XML payload throws rather than passing as an empty feed")
func rssRejectsNonXML() throws {
    #expect(throws: NewsError.self) {
        try RSSNewsProvider.parse(Data("<html><body>Sign in to continue".utf8), source: nil, fallbackSource: "ex.com")
    }
}

@Test("feeds merge round-robin so the panel's few slots come from different publishers")
func rssInterleavesForSourceDiversity() {
    let bbc = [
        NewsHeadline(id: "b1", title: "BBC one", source: "BBC"),
        NewsHeadline(id: "b2", title: "BBC two", source: "BBC"),
    ]
    let npr = [
        NewsHeadline(id: "n1", title: "NPR one", source: "NPR"),
        NewsHeadline(id: "n2", title: "NPR two", source: "NPR"),
    ]

    let merged = RSSNewsProvider.interleave([bbc, npr])

    #expect(merged.map(\.id) == ["b1", "n1", "b2", "n2"])
}

@Test("the same story syndicated to two feeds collapses to one row (by id and by title)")
func rssDeduplicatesAcrossFeeds() {
    let first = [NewsHeadline(id: "shared", title: "Same wire story", source: "AP")]
    let second = [
        NewsHeadline(id: "shared", title: "Different title, same id", source: "Other"),
        NewsHeadline(id: "other-id", title: "same wire story", source: "Other"),
        NewsHeadline(id: "fresh", title: "Genuinely different", source: "Other"),
    ]

    let merged = RSSNewsProvider.interleave([first, second])

    #expect(merged.map(\.id) == ["shared", "fresh"])
}

@Test("a shorter feed does not stall the merge; empty feeds contribute nothing")
func rssInterleaveHandlesUnevenLists() {
    let short = [NewsHeadline(id: "s1", title: "Short one", source: "A")]
    let long = [
        NewsHeadline(id: "l1", title: "Long one", source: "B"),
        NewsHeadline(id: "l2", title: "Long two", source: "B"),
    ]

    #expect(RSSNewsProvider.interleave([short, [], long]).map(\.id) == ["s1", "l1", "l2"])
    #expect(RSSNewsProvider.interleave([]).isEmpty)
    #expect(RSSNewsProvider.interleave([[], []]).isEmpty)
}

@Test("a profile with no configured feeds fails honestly rather than inventing a source")
func rssRequiresConfiguredFeeds() async throws {
    let catalog = NewsProfileCatalog(
        language: "en", defaultCategory: "top", profiles: ["broad": "top"]
    )
    await #expect(throws: NewsError.self) {
        try await RSSNewsProvider(catalog: catalog).headlines(profile: "broad", apiToken: "")
    }
}

@Test("feeds come from config: the profile's list, else defaultFeeds, else none")
func rssResolvesFeedsFromConfig() {
    let tech = NewsFeed(url: "https://ex.com/tech.xml", source: "Ars Technica")
    let world = NewsFeed(url: "https://ex.com/world.xml", source: "BBC News")
    let catalog = NewsProfileCatalog(
        language: "en",
        defaultCategory: "top",
        profiles: ["broad": "top"],
        feeds: ["engineering": [tech]],
        defaultFeeds: [world]
    )

    #expect(catalog.feeds(for: "engineering") == [tech])
    #expect(catalog.feeds(for: "broad") == [world], "falls back to defaultFeeds")

    let bare = NewsProfileCatalog(language: "en", defaultCategory: "top", profiles: [:])
    #expect(bare.feeds(for: "broad").isEmpty)
}

@Test("the configured publisher name wins over the feed's own marketing title")
func rssPrefersConfiguredSource() throws {
    let feed = """
    <rss version="2.0"><channel>
      <title>www.espn.com - TOP</title>
      <item><title>Trade deadline recap</title><link>https://ex.com/a</link></item>
    </channel></rss>
    """
    let items = try RSSNewsProvider.parse(Data(feed.utf8), source: "ESPN", fallbackSource: "ex.com")
    #expect(items[0].source == "ESPN")
}

@Test("the shipped config parses, and every feed carries a URL and a display name")
func rssShippedConfigIsUsable() throws {
    let configDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("config", isDirectory: true)
    let catalog = try #require(NewsProfileCatalog.load(configDirectory: configDirectory))

    for profile in catalog.profiles.keys {
        let feeds = catalog.feeds(for: profile)
        #expect(!feeds.isEmpty, "profile \(profile) has no fallback feeds")
        for feed in feeds {
            #expect(URL(string: feed.url)?.host != nil, "\(feed.url) is not a usable URL")
            #expect(feed.source?.isEmpty == false, "\(feed.url) has no display name")
        }
    }
}
#endif
