// New/hot movie + TV releases from TMDB (NIC-134).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Fetches the current trending movies and TV shows from TMDB (`api.themoviedb.org`) with
/// `URLSession`. The API token is supplied per call (resolved from the Keychain by the
/// ``ReleasesPublisher``, Increment 5) and sent as a **v4 Bearer token in the `Authorization`
/// header** — never in the URL or query string, so it can't leak into logs or diagnostics
/// (FR-OBS-03). Mirrors the read-only ephemeral-`URLSession` pattern the weather + network
/// speed-test adapters use.
///
/// Source endpoint is `/trending/all/week`: a single call returning a mixed, rotating,
/// popularity-ordered set of movies, TV, and people. People are filtered out; the rest map to
/// ``ReleaseItem``. Any transport, non-2xx, or decode failure throws
/// ``ReleaseError/providerFailed(_:)`` so the widget degrades to an honest "unavailable" —
/// never a fabricated list. The token is not the provider's to validate: a 401 is just an
/// unsuccessful response like any other.
public struct TMDBReleasesProvider: ReleaseProvider {
    private let session: URLSession
    private let host: String
    private let limit: Int

    public init(
        session: URLSession? = nil,
        host: String = "https://api.themoviedb.org",
        limit: Int = 8,
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
        self.limit = limit
    }

    public func trending(apiToken: String) async throws -> [ReleaseItem] {
        guard let request = Self.makeRequest(host: host, apiToken: apiToken) else {
            throw ReleaseError.providerFailed("Could not build the releases request URL.")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ReleaseError.providerFailed("The releases service returned an unsuccessful response.")
            }
            return try Self.parse(data, limit: limit)
        } catch let error as ReleaseError {
            throw error
        } catch {
            throw ReleaseError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the trending request. The token rides the `Authorization` header (v4 Bearer),
    /// deliberately NOT the URL — so the secret never appears in a logged/cached request URL.
    static func makeRequest(host: String, apiToken: String) -> URLRequest? {
        guard var components = URLComponents(string: "\(host)/3/trending/all/week") else { return nil }
        components.queryItems = [URLQueryItem(name: "language", value: "en-US")]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let id: Int
            let mediaType: String
            let title: String?
            let name: String?
            let releaseDate: String?
            let firstAirDate: String?
            enum CodingKeys: String, CodingKey {
                case id
                case mediaType = "media_type"
                case title
                case name
                case releaseDate = "release_date"
                case firstAirDate = "first_air_date"
            }
        }
        let results: [Item]
    }

    /// Decodes a TMDB trending payload into up to `limit` ``ReleaseItem``s. People are dropped
    /// (only `movie`/`tv` map to a ``ReleaseMediaType``); an item with no usable title is
    /// skipped rather than shown blank; a missing/blank date yields a nil year, never a
    /// fabricated one. Throws ``ReleaseError/providerFailed(_:)`` on malformed JSON.
    static func parse(_ data: Data, limit: Int) throws -> [ReleaseItem] {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ReleaseError.providerFailed("Could not parse the releases response.")
        }

        var items: [ReleaseItem] = []
        for entry in decoded.results {
            guard let mediaType = ReleaseMediaType(rawValue: entry.mediaType) else { continue }
            let title = (entry.title ?? entry.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { continue }
            let year = Self.year(from: entry.releaseDate ?? entry.firstAirDate)
            items.append(ReleaseItem(id: String(entry.id), title: title, mediaType: mediaType, year: year))
            if items.count >= limit { break }
        }
        return items
    }

    /// The four-digit year at the start of a TMDB date string (`YYYY-MM-DD`), or nil when the
    /// string is absent, blank, or not a leading year — never a guessed value.
    static func year(from date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }
}
#endif
