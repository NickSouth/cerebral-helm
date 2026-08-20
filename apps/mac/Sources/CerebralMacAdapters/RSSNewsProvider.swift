// The free RSS/Atom fallback behind the metered news provider (the news quota fix, increment 2).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Fetches one relevance profile's headlines from the publishers' own RSS/Atom feeds — no API key,
/// no quota, no account. Sits behind ``NewsDataProvider`` in a ``FallbackNewsProvider`` chain, so
/// the News panel keeps working through a rate limit, an outage, or an unconfigured key.
///
/// The feed list per profile comes from `config/news/profiles.json` (AC5's rule: source
/// configuration lives in config, never hardcoded in the adapter), so adding or swapping a
/// publisher is an edit to that file rather than a code change.
///
/// A profile's feeds are fetched **concurrently and independently**: one dead or slow feed costs
/// its own results, never the whole profile. Results are merged **round-robin** — the first item of
/// each feed, then the second — so the four headlines the panel shows come from four different
/// publishers rather than whichever feed happens to sort first. Duplicates are dropped by id and by
/// case-insensitive title, which is how the same wire story syndicated to several feeds collapses
/// to one row.
///
/// Nothing is fabricated: an item without a usable title is skipped, and an item without a link
/// yields a nil `url` (rendered as non-interactive text).
public struct RSSNewsProvider: NewsProvider {
    private let session: URLSession
    private let catalog: NewsProfileCatalog
    private let limit: Int
    private let maximumFeeds: Int

    public init(
        catalog: NewsProfileCatalog,
        session: URLSession? = nil,
        // The candidate pool for interest ranking (NIC-223), not the panel's slot count. Free
        // for RSS: these items were already fetched and parsed, then thrown away.
        limit: Int = 10,
        maximumFeeds: Int = 4,
        resourceTimeout: TimeInterval = 12
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.catalog = catalog
        self.limit = limit
        self.maximumFeeds = maximumFeeds
    }

    /// `apiToken` is ignored — that is the point of this provider. It is part of the ``NewsProvider``
    /// contract because the metered implementations need it.
    public func headlines(profile: String, apiToken _: String) async throws -> [NewsHeadline] {
        let feeds = catalog.feeds(for: profile).prefix(maximumFeeds)
            .compactMap { feed in URL(string: feed.url).map { ($0, feed.source) } }
        guard !feeds.isEmpty else {
            throw NewsError.providerFailed("No fallback feeds are configured for this profile.")
        }

        // Fetch every feed concurrently; a feed that fails contributes nothing rather than failing
        // the profile. The results are indexed so the round-robin merge stays deterministic
        // regardless of which feed responds first.
        var lists = [[NewsHeadline]](repeating: [], count: feeds.count)
        await withTaskGroup(of: (Int, [NewsHeadline]).self) { group in
            for (index, feed) in feeds.enumerated() {
                group.addTask { (index, (try? await fetchFeed(feed.0, source: feed.1)) ?? []) }
            }
            for await (index, headlines) in group {
                lists[index] = headlines
            }
        }

        let merged = Self.interleave(lists)
        guard !merged.isEmpty else {
            throw NewsError.providerFailed("No fallback feed returned a usable headline.")
        }
        return Array(merged.prefix(limit))
    }

    private func fetchFeed(_ url: URL, source: String?) async throws -> [NewsHeadline] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/rss+xml, application/atom+xml, application/xml", forHTTPHeaderField: "accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NewsError.providerFailed("The feed returned an unsuccessful response.")
        }
        return try Self.parse(data, source: source, fallbackSource: url.host ?? "")
    }

    // MARK: - Pure helpers (unit-tested)

    /// Merges each feed's headlines round-robin, dropping duplicates by id and by case-insensitive
    /// title. Round-robin (rather than concatenation) is what gives the panel's few slots source
    /// diversity: one prolific feed cannot crowd out the rest.
    static func interleave(_ lists: [[NewsHeadline]]) -> [NewsHeadline] {
        var merged: [NewsHeadline] = []
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()
        let depth = lists.map(\.count).max() ?? 0
        for index in 0..<depth {
            for list in lists where index < list.count {
                let item = list[index]
                let titleKey = item.title.lowercased()
                guard !seenIDs.contains(item.id), !seenTitles.contains(titleKey) else { continue }
                seenIDs.insert(item.id)
                seenTitles.insert(titleKey)
                merged.append(item)
            }
        }
        return merged
    }

    /// Parses an RSS 2.0 or Atom feed into headlines. Both shapes are supported because real
    /// publishers ship both (BBC and NPR are RSS `<item>`; The Verge is Atom `<entry>`), and a feed
    /// silently yielding nothing because of its dialect would be an invisible failure.
    ///
    /// Throws ``NewsError/providerFailed(_:)`` when the payload is not parseable XML, so a captive
    /// portal's HTML login page can never be mistaken for an empty feed.
    ///
    /// The row's source label prefers the configured name, then the feed's own channel title, then
    /// the host — each one real, none invented.
    static func parse(_ data: Data, source configured: String?, fallbackSource: String) throws -> [NewsHeadline] {
        let parser = XMLParser(data: data)
        let delegate = FeedParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw NewsError.providerFailed("Could not parse the feed response.")
        }
        let source = configured?.isEmpty == false
            ? (configured ?? "")
            : (delegate.channelTitle.isEmpty ? fallbackSource : delegate.channelTitle)
        return delegate.entries.compactMap { entry in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let link = entry.link.trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = entry.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            // The feed's own guid/id is the stable row key; a link is the next best thing, and a
            // title-derived key is the last resort so an item is never dropped for lacking both.
            let id = !identifier.isEmpty ? identifier : (!link.isEmpty ? link : "feed:\(source):\(title)")
            return NewsHeadline(id: id, title: title, source: source, url: link.isEmpty ? nil : link)
        }
    }
}

/// Collects `<item>`/`<entry>` titles, links and ids from a feed.
///
/// The element names are shared between the two dialects and between feed and item level, so the
/// delegate tracks whether it is inside an entry and only takes the **first** value for each field
/// — that is what keeps a channel-level `<title>` out of the headlines and an Atom `<entry><id>`
/// distinct from the feed's own `<id>`. CDATA is handled explicitly: most publishers (BBC among
/// them) wrap titles in CDATA, and a character-only delegate would return every title blank.
private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    struct Entry {
        var title = ""
        var link = ""
        var identifier = ""
    }

    private(set) var entries: [Entry] = []
    private(set) var channelTitle = ""

    private var text = ""
    private var current: Entry?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        if elementName == "item" || elementName == "entry" {
            current = Entry()
            return
        }
        // Atom carries the article URL in the link element's `href` attribute, with no element
        // text at all; `rel="alternate"` (or an absent rel) is the human-readable article.
        if elementName == "link", current != nil, let href = attributeDict["href"] {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate", current?.link.isEmpty == true {
                current?.link = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        if elementName == "item" || elementName == "entry" {
            if let current { entries.append(current) }
            current = nil
            return
        }

        guard current != nil else {
            // Feed level: the channel's own title is the source name shown on every headline row.
            if elementName == "title", channelTitle.isEmpty { channelTitle = value }
            return
        }

        switch elementName {
        case "title" where current?.title.isEmpty == true:
            current?.title = value
        case "link" where current?.link.isEmpty == true && !value.isEmpty:
            current?.link = value
        case "guid" where current?.identifier.isEmpty == true,
             "id" where current?.identifier.isEmpty == true:
            current?.identifier = value
        default:
            break
        }
    }
}
#endif
