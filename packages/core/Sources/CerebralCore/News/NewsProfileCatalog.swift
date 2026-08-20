import Foundation

/// One free RSS/Atom feed backing a news profile when the metered provider is unavailable.
///
/// `source` is the publisher name the panel shows on each headline row. It is configured rather
/// than taken from the feed because feed titles are marketing copy, not labels — the live feeds
/// call themselves "Al Jazeera – Breaking News, World News and Video from Al Jazeera" and
/// "www.espn.com - TOP", neither of which belongs in a narrow rail. Omitting it falls back to the
/// feed's own channel title, which is honest but usually ugly.
public struct NewsFeed: Decodable, Equatable, Sendable {
    /// The feed's absolute URL.
    public let url: String
    /// The publisher name to display; nil falls back to the feed's own title.
    public let source: String?

    public init(url: String, source: String? = nil) {
        self.url = url
        self.source = source
    }
}

/// The per-mode news relevance mapping (NIC-127), decoded from `config/news/profiles.json`. Each
/// mode config's `newsProfile` (e.g. "broad", "engineering") resolves here to one or more provider
/// categories, so the source configuration lives in config, not hardcoded in the adapter (FR-CFG,
/// AC5). Provider-neutral: the value is an opaque category string a concrete ``NewsProvider`` maps
/// to its own query (NewsData.io categories, Increment 5). An unmapped profile falls back to
/// ``defaultCategory`` rather than failing — a mode always gets *some* news.
public struct NewsProfileCatalog: Decodable, Equatable, Sendable {
    /// The language code passed to the provider (e.g. "en").
    public let language: String
    /// The category used when a profile has no explicit mapping.
    public let defaultCategory: String
    /// newsProfile → category string (comma-separated categories allowed).
    public let profiles: [String: String]
    /// newsProfile → the free RSS/Atom feeds backing it when the metered provider is unavailable.
    /// Optional so an older config file still decodes (the fallback simply has nothing to fetch).
    public let feeds: [String: [NewsFeed]]?
    /// The feeds used when a profile has no explicit list.
    public let defaultFeeds: [NewsFeed]?
    /// Whether the user's interests are also sent to the metered provider as a `q=` search:
    /// `"q"` (the default) or `"off"`. Optional so an older config file still decodes.
    ///
    /// A switch rather than a constant because the combination is the one part of NIC-223 that
    /// depends on the provider's continued goodwill: `q` alongside `category` is verified to work
    /// on the free tier today, but if it ever starts returning 422 every metered request would
    /// silently fall through to the RSS source. Turning it off is then a one-line config edit, not
    /// a rebuild.
    public let interestQuery: String?

    /// True when interest terms should ride along as a `q=` search.
    public var sendsInterestQuery: Bool { (interestQuery ?? "q") == "q" }

    public init(
        language: String,
        defaultCategory: String,
        profiles: [String: String],
        feeds: [String: [NewsFeed]]? = nil,
        defaultFeeds: [NewsFeed]? = nil,
        interestQuery: String? = nil
    ) {
        self.language = language
        self.defaultCategory = defaultCategory
        self.profiles = profiles
        self.feeds = feeds
        self.defaultFeeds = defaultFeeds
        self.interestQuery = interestQuery
    }

    /// The category string for a mode's `newsProfile`, or ``defaultCategory`` when it has no
    /// explicit mapping (never nil — a mode always resolves to some news).
    public func category(for profile: String) -> String {
        profiles[profile] ?? defaultCategory
    }

    /// The fallback feeds for a mode's `newsProfile`, falling back to ``defaultFeeds`` and then to
    /// none. Empty means the free fallback cannot serve this profile — the caller degrades to the
    /// metered provider's own outcome rather than inventing a source.
    public func feeds(for profile: String) -> [NewsFeed] {
        feeds?[profile] ?? defaultFeeds ?? []
    }

    /// Decodes a catalog from `config/news/profiles.json` bytes.
    public static func decode(from data: Data) throws -> NewsProfileCatalog {
        try JSONDecoder().decode(NewsProfileCatalog.self, from: data)
    }

    /// Loads the catalog from `<configDirectory>/news/profiles.json`, or nil when the file is
    /// absent or malformed — the caller degrades to an honest no-news state rather than crashing
    /// (mirrors ``ModeLayoutCatalog/load(configDirectory:)``).
    public static func load(configDirectory: URL) -> NewsProfileCatalog? {
        let url = configDirectory
            .appendingPathComponent("news", isDirectory: true)
            .appendingPathComponent("profiles.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(from: data)
    }
}
