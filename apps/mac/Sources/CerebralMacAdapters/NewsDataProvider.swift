// Per-mode headlines from NewsData.io (NIC-127).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Fetches the current headlines for one relevance profile from NewsData.io (`newsdata.io`) with
/// `URLSession`. The API key is supplied per call (resolved from the Keychain by the
/// ``NewsPublisher``, Increment 7) and sent in the **`X-ACCESS-KEY` header** — never in the URL or
/// query string, so it can't leak into logs or diagnostics (FR-OBS-03). Mirrors the read-only
/// ephemeral-`URLSession` pattern the TMDB releases + weather adapters use.
///
/// The profile → category mapping is not hardcoded here: it comes from the injected
/// ``NewsProfileCatalog`` (loaded from `config/news/profiles.json`), satisfying AC5. The endpoint
/// is `/api/1/latest?category=<categories>&language=<lang>`. Any transport, non-2xx, or decode
/// failure throws ``NewsError/providerFailed(_:)`` so the panel degrades to an honest "unavailable"
/// — never a fabricated list. Headlines are capped at `limit` (default four); an item without a
/// title is skipped, and a missing link yields a nil `url` (non-clickable, never fabricated).
public struct NewsDataProvider: NewsProvider {
    private let session: URLSession
    private let host: String
    private let catalog: NewsProfileCatalog
    private let limit: Int

    public init(
        catalog: NewsProfileCatalog,
        session: URLSession? = nil,
        host: String = "https://newsdata.io",
        limit: Int = 4,
        resourceTimeout: TimeInterval = 15
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
        self.catalog = catalog
        self.limit = limit
    }

    public func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
        let category = catalog.category(for: profile)
        guard let request = Self.makeRequest(
            host: host, category: category, language: catalog.language, apiToken: apiToken
        ) else {
            throw NewsError.providerFailed("Could not build the news request URL.")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NewsError.providerFailed("The news service returned an unsuccessful response.")
            }
            return Array(try Self.parse(data).prefix(limit))
        } catch let error as NewsError {
            throw error
        } catch {
            throw NewsError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the latest-headlines request. The key rides the `X-ACCESS-KEY` header, deliberately
    /// NOT the URL — so the secret never appears in a logged/cached request URL (FR-OBS-03). The
    /// category and language are data (not secret), so they stay in the query.
    static func makeRequest(host: String, category: String, language: String, apiToken: String) -> URLRequest? {
        guard var components = URLComponents(string: "\(host)/api/1/latest") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "language", value: language),
            // Restrict to NewsData's top-priority (major, reputable) domains — a source-quality
            // filter that keeps the low-quality aggregator blogs out of the panel (owner request).
            URLQueryItem(name: "prioritydomain", value: "top"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiToken, forHTTPHeaderField: "X-ACCESS-KEY")
        return request
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let articleId: String?
            let title: String?
            let link: String?
            let sourceName: String?
            let sourceId: String?
            enum CodingKeys: String, CodingKey {
                case articleId = "article_id"
                case title
                case link
                case sourceName = "source_name"
                case sourceId = "source_id"
            }
        }
        // `results` is an array on success; on an error payload NewsData returns it as an object,
        // which fails to decode here → an honest `providerFailed`, never a fabricated list.
        let results: [Item]
    }

    /// Decodes a NewsData `latest` payload into headlines. An item without a usable title is skipped
    /// rather than shown blank; a missing/blank `link` yields a nil `url` (non-clickable, never
    /// fabricated); the source falls back from `source_name` to `source_id` to empty. Throws
    /// ``NewsError/providerFailed(_:)`` on malformed JSON (including an error payload).
    static func parse(_ data: Data) throws -> [NewsHeadline] {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NewsError.providerFailed("Could not parse the news response.")
        }

        var items: [NewsHeadline] = []
        var seenTitles = Set<String>()
        for entry in decoded.results {
            guard let id = entry.articleId, !id.isEmpty else { continue }
            let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { continue }
            // Drop syndicated duplicates — the same story from several sources shares a title but
            // has distinct article ids, and showing it twice looks broken (case-insensitive).
            guard seenTitles.insert(title.lowercased()).inserted else { continue }
            let source = (entry.sourceName ?? entry.sourceId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let link = entry.link?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (link?.isEmpty == false) ? link : nil
            items.append(NewsHeadline(id: id, title: title, source: source, url: url))
        }
        return items
    }
}
#endif
