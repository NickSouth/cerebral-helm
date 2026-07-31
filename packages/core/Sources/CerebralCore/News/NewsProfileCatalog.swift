import Foundation

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

    public init(language: String, defaultCategory: String, profiles: [String: String]) {
        self.language = language
        self.defaultCategory = defaultCategory
        self.profiles = profiles
    }

    /// The category string for a mode's `newsProfile`, or ``defaultCategory`` when it has no
    /// explicit mapping (never nil — a mode always resolves to some news).
    public func category(for profile: String) -> String {
        profiles[profile] ?? defaultCategory
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
