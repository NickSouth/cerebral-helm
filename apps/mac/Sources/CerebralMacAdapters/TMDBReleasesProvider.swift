// New/hot movie + TV releases from TMDB (NIC-134).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Fetches the current trending movies and TV shows from TMDB (`api.themoviedb.org`) with
/// `URLSession`. The API token is supplied per call (resolved from the Keychain by the
/// ``ReleasesPublisher``, Increment 5) and sent as a **v4 Bearer token in the `Authorization`
/// header** — never in the URL or query string, so it can't leak into logs or diagnostics
/// (FR-OBS-03). Mirrors the read-only ephemeral-`URLSession` pattern the weather + network
/// speed-test adapters use.
///
/// Source endpoint is `/trending/all/week`: a single call returning a mixed set of movies, TV,
/// and people. People are dropped; the rest are **balanced** into an even movie/TV split so the
/// widget always shows shows alongside films (owner feedback), then posters are fetched and
/// embedded as `data:` URIs (the dashboard's `cerebral://` origin does not load external image
/// URLs, so the same native-fetch pattern as favicons is used). Any transport, non-2xx, or
/// decode failure throws ``ReleaseError/providerFailed(_:)`` so the widget degrades to an honest
/// "unavailable" — never a fabricated list. A poster that can't be fetched is simply omitted.
public struct TMDBReleasesProvider: ReleaseProvider {
    private let session: URLSession
    private let host: String
    private let posterBaseURL: String
    /// How many of each media type (movie, TV) to surface — the widget pages through them 2×2,
    /// so 4 of each yields two balanced pages of "2 movies + 2 shows".
    private let perType: Int
    private let fetchPosters: Bool

    public init(
        session: URLSession? = nil,
        host: String = "https://api.themoviedb.org",
        posterBaseURL: String = "https://image.tmdb.org/t/p/w185",
        perType: Int = 4,
        fetchPosters: Bool = true,
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
        self.posterBaseURL = posterBaseURL
        self.perType = perType
        self.fetchPosters = fetchPosters
    }

    public func trending(apiToken: String) async throws -> [ReleaseItem] {
        guard let request = Self.makeRequest(host: host, apiToken: apiToken) else {
            throw ReleaseError.providerFailed("Could not build the releases request URL.")
        }
        let parsed: [Parsed]
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ReleaseError.providerFailed("The releases service returned an unsuccessful response.")
            }
            parsed = Self.balanced(try Self.parse(data), perType: perType)
        } catch let error as ReleaseError {
            throw error
        } catch {
            throw ReleaseError.providerFailed(error.localizedDescription)
        }

        // Fetch each poster (best-effort, in parallel) and build the final items. A poster miss
        // is honest — the card falls back to a title placeholder, never a broken image.
        var items: [ReleaseItem] = []
        for entry in parsed {
            let poster = fetchPosters ? await fetchPoster(path: entry.posterPath) : nil
            items.append(ReleaseItem(
                id: entry.id, title: entry.title, mediaType: entry.mediaType,
                year: entry.year, posterImage: poster
            ))
        }
        return items
    }

    private func fetchPoster(path: String?) async -> String? {
        guard let url = Self.posterURL(base: posterBaseURL, path: path) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return Self.posterDataURI(data)
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

    /// The full poster URL for a TMDB `poster_path` (e.g. `/abc.jpg`), or nil when the path is
    /// absent or blank — never a fabricated image.
    static func posterURL(base: String, path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: base + path)
    }

    /// A parsed trending entry, carrying the TMDB `poster_path` the poster fetch needs (kept
    /// separate from ``ReleaseItem``, which holds the fetched image, not the path).
    struct Parsed: Equatable {
        let id: String
        let title: String
        let mediaType: ReleaseMediaType
        let year: Int?
        let posterPath: String?
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let id: Int
            let mediaType: String
            let title: String?
            let name: String?
            let releaseDate: String?
            let firstAirDate: String?
            let posterPath: String?
            enum CodingKeys: String, CodingKey {
                case id
                case mediaType = "media_type"
                case title
                case name
                case releaseDate = "release_date"
                case firstAirDate = "first_air_date"
                case posterPath = "poster_path"
            }
        }
        let results: [Item]
    }

    /// Decodes a TMDB trending payload into parsed entries. People are dropped (only `movie`/`tv`
    /// map to a ``ReleaseMediaType``); an item with no usable title is skipped rather than shown
    /// blank; a missing/blank date yields a nil year. Throws ``ReleaseError/providerFailed(_:)``
    /// on malformed JSON.
    static func parse(_ data: Data) throws -> [Parsed] {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ReleaseError.providerFailed("Could not parse the releases response.")
        }

        var items: [Parsed] = []
        for entry in decoded.results {
            guard let mediaType = ReleaseMediaType(rawValue: entry.mediaType) else { continue }
            let title = (entry.title ?? entry.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { continue }
            items.append(Parsed(
                id: String(entry.id), title: title, mediaType: mediaType,
                year: Self.year(from: entry.releaseDate ?? entry.firstAirDate),
                posterPath: entry.posterPath
            ))
        }
        return items
    }

    /// Interleaves up to `perType` movies and `perType` shows — [movie, tv, movie, tv, …] — so
    /// each 2×2 page the widget renders is "2 movies + 2 shows" (owner feedback). When one type
    /// is short, the result is simply shorter on that type; order within a type is preserved
    /// (TMDB's popularity order).
    static func balanced(_ items: [Parsed], perType: Int) -> [Parsed] {
        var movies = items.filter { $0.mediaType == .movie }.prefix(perType).makeIterator()
        var shows = items.filter { $0.mediaType == .tv }.prefix(perType).makeIterator()
        var result: [Parsed] = []
        for _ in 0..<perType {
            if let m = movies.next() { result.append(m) }
            if let s = shows.next() { result.append(s) }
        }
        return result
    }

    /// The four-digit year at the start of a TMDB date string (`YYYY-MM-DD`), or nil when the
    /// string is absent, blank, or not a leading year — never a guessed value.
    static func year(from date: String?) -> Int? {
        guard let date, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

    /// Validates poster bytes as a real image and returns a self-contained `data:` URI (base64),
    /// sniffing JPEG vs PNG for the correct MIME. Returns nil for undecodable bytes (an HTML
    /// error page), an empty body, or an over-cap payload — an honest miss, never a broken image.
    static func posterDataURI(_ data: Data, byteCap: Int = 200_000) -> String? {
        guard !data.isEmpty, data.count <= byteCap, NSImage(data: data) != nil else { return nil }
        let mime: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mime = "image/png"
        } else if data.starts(with: [0xFF, 0xD8]) {
            mime = "image/jpeg"
        } else {
            return nil // not a poster format we vouch for
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
#endif
