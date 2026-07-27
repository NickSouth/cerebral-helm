// The currently-playing track from the Spotify Web API (NIC-133).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Reads the user's current Spotify playback from `GET /me/player` (NIC-133) with `URLSession` —
/// the full player state, so one call yields the track, the **active device**, and the playback
/// **progress**/duration for the widget's progress bar. The access token is supplied per call (the ``SpotifyAuthSession``
/// resolves and refreshes it, Increment 4) and rides the **`Authorization: Bearer` header** — never
/// the URL, so it can't leak into logs (FR-OBS-03). Mirrors the ephemeral-`URLSession` +
/// pure-static-helper pattern of the TMDB/Finnhub/GitHub adapters.
///
/// A `204 No Content` (nothing playing / no active device) returns `nil` — a healthy empty, not a
/// failure. A `401` means the token is no longer accepted → ``SpotifyPlaybackError/notConnected``
/// ("reconnect"). Any other transport/non-2xx/decode failure → ``providerFailed`` (a generic
/// "unavailable" — never a fabricated track). Album artwork is fetched natively and embedded as a
/// `data:` URI (the dashboard's `cerebral://` origin does not load external image URLs); a fetch
/// miss simply omits the artwork, so the card falls back to its music-note placeholder.
public struct SpotifyWebPlaybackProvider: SpotifyPlaybackProvider {
    private let session: URLSession
    private let host: String
    private let fetchArtwork: Bool

    public init(
        session: URLSession? = nil,
        host: String = "https://api.spotify.com",
        fetchArtwork: Bool = true,
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
        self.fetchArtwork = fetchArtwork
    }

    public func nowPlaying(accessToken: String) async throws -> SpotifyNowPlaying? {
        guard let request = Self.makeRequest(host: host, accessToken: accessToken) else {
            throw SpotifyPlaybackError.providerFailed("Could not build the now-playing request URL.")
        }
        let parsed: Parsed?
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyPlaybackError.providerFailed("The Spotify player did not return an HTTP response.")
            }
            switch http.statusCode {
            case 204:
                return nil // nothing playing / no active device — a healthy empty
            case 401:
                throw SpotifyPlaybackError.notConnected // token rejected → reconnect
            case 200..<300:
                parsed = try Self.parse(data)
            default:
                throw SpotifyPlaybackError.providerFailed("The Spotify player returned an unsuccessful response.")
            }
        } catch let error as SpotifyPlaybackError {
            throw error
        } catch {
            throw SpotifyPlaybackError.providerFailed(error.localizedDescription)
        }

        guard let parsed else { return nil } // 200 but nothing showable (ad / private session)
        let artwork = (fetchArtwork ? await fetchArtworkDataURI(parsed.artworkURL) : nil)
        return SpotifyNowPlaying(
            track: parsed.track, artist: parsed.artist, album: parsed.album,
            artworkImage: artwork, isPlaying: parsed.isPlaying,
            deviceName: parsed.deviceName, progressMs: parsed.progressMs, durationMs: parsed.durationMs
        )
    }

    private func fetchArtworkDataURI(_ url: URL?) async -> String? {
        guard let url else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return Self.artworkDataURI(data)
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the now-playing request. The token rides the `Authorization` header (Bearer),
    /// deliberately NOT the URL — so the secret never appears in a logged/cached request URL.
    static func makeRequest(host: String, accessToken: String) -> URLRequest? {
        guard let url = URL(string: "\(host)/v1/me/player") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// A parsed now-playing item, carrying the artwork URL the image fetch needs (kept separate from
    /// ``SpotifyNowPlaying``, which holds the fetched image, not the URL).
    struct Parsed: Equatable {
        let track: String
        let artist: String
        let album: String?
        let isPlaying: Bool
        let artworkURL: URL?
        let deviceName: String?
        let progressMs: Int?
        let durationMs: Int?
    }

    struct Response: Decodable {
        let is_playing: Bool?
        let progress_ms: Int?
        let device: Device?
        let item: Item?
        struct Device: Decodable { let name: String? }
        struct Item: Decodable {
            let name: String?
            let duration_ms: Int?
            let artists: [Artist]?
            let album: Album?
            let images: [Image]? // episodes carry images directly on the item
            let show: Show?
            struct Artist: Decodable { let name: String? }
            struct Album: Decodable {
                let name: String?
                let images: [Image]?
            }
            struct Show: Decodable { let name: String? }
        }
        struct Image: Decodable {
            let url: String?
            let width: Int?
        }
    }

    /// Decodes a currently-playing payload into a ``Parsed`` item, or nil when there is nothing
    /// showable (no item, or an item with no title — e.g. an ad or a private session). The artist is
    /// the joined track artists, falling back to the show name for a podcast episode; the album is
    /// omitted for episodes. Throws ``SpotifyPlaybackError/providerFailed(_:)`` on malformed JSON.
    static func parse(_ data: Data) throws -> Parsed? {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SpotifyPlaybackError.providerFailed("Could not parse the Spotify player response.")
        }
        guard let item = decoded.item else { return nil }
        let track = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !track.isEmpty else { return nil }

        let artists = (item.artists ?? [])
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let artist = artists.isEmpty
            ? (item.show?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : artists.joined(separator: ", ")

        let album = item.album?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = item.album?.images ?? item.images ?? []
        let deviceName = decoded.device?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(
            track: track, artist: artist,
            album: (album?.isEmpty == false) ? album : nil,
            isPlaying: decoded.is_playing ?? false,
            artworkURL: pickImageURL(from: images),
            deviceName: (deviceName?.isEmpty == false) ? deviceName : nil,
            progressMs: decoded.progress_ms,
            durationMs: item.duration_ms
        )
    }

    /// Chooses an artwork URL sized for the small tile: the smallest image at least 160px wide
    /// (enough for a 64pt tile at 2×, keeping the embedded data URI small), else the largest
    /// available. When no widths are given, Spotify lists largest-first, so the last is the smallest.
    static func pickImageURL(from images: [Response.Image]) -> URL? {
        let withURL = images.filter { ($0.url?.isEmpty == false) }
        guard !withURL.isEmpty else { return nil }
        let sized = withURL.compactMap { image -> (Int, String)? in
            guard let width = image.width, let url = image.url else { return nil }
            return (width, url)
        }
        if !sized.isEmpty {
            if let atLeast160 = sized.filter({ $0.0 >= 160 }).min(by: { $0.0 < $1.0 }) {
                return URL(string: atLeast160.1)
            }
            if let largest = sized.max(by: { $0.0 < $1.0 }) {
                return URL(string: largest.1)
            }
        }
        return withURL.last?.url.flatMap { URL(string: $0) }
    }

    /// Validates artwork bytes as a real image and returns a self-contained `data:` URI (base64),
    /// sniffing JPEG vs PNG for the MIME. Returns nil for undecodable bytes, an empty body, or an
    /// over-cap payload — an honest miss, never a broken image (the same guard the TMDB posters use).
    static func artworkDataURI(_ data: Data, byteCap: Int = 200_000) -> String? {
        guard !data.isEmpty, data.count <= byteCap, NSImage(data: data) != nil else { return nil }
        let mime: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mime = "image/png"
        } else if data.starts(with: [0xFF, 0xD8]) {
            mime = "image/jpeg"
        } else {
            return nil
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
#endif
