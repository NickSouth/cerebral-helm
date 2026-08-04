// Spotify playlist creation (quick-actions phase 4) — the `create-playlist` action's actuator.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Creates a playlist in the connected Spotify account via `POST /v1/me/playlists`.
///
/// Shares the Keychain-backed OAuth session with the now-playing publisher and the playback
/// controls, but is a **separate capability**: control is transport, this writes to the user's
/// library, and it needs scopes control never asked for.
///
/// **The scope gap is the interesting failure here.** `playlist-modify-private` /
/// `playlist-modify-public` were added to the requested set alongside this adapter, so a token
/// issued *before* that still works perfectly for playback and is refused for playlists. Spotify
/// answers that with a `403`, which this reports as `permissionDenied` — the form then tells the
/// user to reconnect, rather than implying their account is broken.
///
/// Endpoint, body fields and scopes are from Spotify's Web API reference (checked 2026-08-03). The
/// round trip is **not** smoke-tested: it needs a re-authorized token and would create a real
/// playlist in a real account, so it is a manual verification step.
public struct SpotifyWebPlaylistCapability: SpotifyPlaylistCapability {
    private let authSession: SpotifyAuthSession
    private let session: URLSession
    private let host: String
    private let workspace: any WorkspaceOpening

    public init(
        authSession: SpotifyAuthSession,
        session: URLSession? = nil,
        host: String = "https://api.spotify.com",
        workspace: any WorkspaceOpening = SystemWorkspace(),
        resourceTimeout: TimeInterval = 15
    ) {
        self.authSession = authSession
        self.host = host
        self.workspace = workspace
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
    }

    public func createPlaylist(
        name: String, description: String?, isPublic: Bool
    ) async throws -> SpotifyPlaylistResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeCapabilityError.adapterFailure("A playlist needs a name.")
        }

        let token: String
        do {
            token = try await authSession.accessToken()
        } catch {
            // No stored authorization, or one that can no longer refresh.
            throw NativeCapabilityError.unavailable
        }

        guard let request = Self.makeRequest(
            host: host, name: trimmed, description: description, isPublic: isPublic, accessToken: token
        ) else {
            throw NativeCapabilityError.unavailable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch {
            throw NativeCapabilityError.adapterFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw NativeCapabilityError.unavailable }
        try Self.checkStatus(http.statusCode)

        guard let created = Self.decode(data, fallbackName: trimmed) else {
            throw NativeCapabilityError.adapterFailure("Spotify did not confirm the playlist was created.")
        }

        // Opening is BEST-EFFORT and deliberately cannot fail the create: the playlist exists the
        // moment Spotify answered, and reporting a failure because a window did not come forward
        // would be wrong about the thing that actually matters.
        var opened = false
        if let appURI = Self.appURI(playlistID: created.id) {
            opened = (try? await workspace.openURL(appURI)) != nil
        }
        return SpotifyPlaylistResult(id: created.id, name: created.name, url: created.url, opened: opened)
    }

    /// The `spotify:` URI that opens the **desktop app** at the playlist, rather than a browser tab.
    ///
    /// Derived from the id rather than read from the response: Spotify's create documentation does
    /// not list a `uri` field, and the scheme is a fixed constant. This is not a caller-chosen
    /// destination — the id came from Spotify's own answer a line ago, and the only variable part
    /// is percent-encoded into a single path component.
    static func appURI(playlistID: String) -> URL? {
        let allowed = CharacterSet.alphanumerics
        guard
            !playlistID.isEmpty,
            let escaped = playlistID.addingPercentEncoding(withAllowedCharacters: allowed),
            escaped == playlistID
        else { return nil }
        return URL(string: "spotify:playlist:\(playlistID)")
    }

    // MARK: - Pure helpers (unit-tested)

    /// The create request. The token rides the `Authorization` header, never the URL, so it cannot
    /// leak through a logged request description (FR-OBS-03). `public` is always sent explicitly:
    /// Spotify defaults it to `true`, and inheriting that would publish to someone's profile
    /// because a field was omitted.
    static func makeRequest(
        host: String, name: String, description: String?, isPublic: Bool, accessToken: String
    ) -> URLRequest? {
        guard let url = URL(string: host + "/v1/me/playlists") else { return nil }
        var body: [String: Any] = ["name": name, "public": isPublic]
        if let description, !description.isEmpty { body["description"] = description }
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = encoded
        return request
    }

    /// 2xx is success. `403` is the scope gap — a token predating the playlist scopes — and `401`
    /// is a dead authorization; both are `permissionDenied`, which the form renders as "reconnect".
    static func checkStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw NativeCapabilityError.permissionDenied
        case 429:
            throw NativeCapabilityError.adapterFailure("Spotify's rate limit was reached. Try again shortly.")
        default:
            throw NativeCapabilityError.adapterFailure("Spotify returned HTTP \(statusCode).")
        }
    }

    /// Reads the created playlist. The URL comes from Spotify's own `external_urls.spotify` and is
    /// never constructed locally; its absence is reported as absent rather than guessed at.
    static func decode(_ data: Data, fallbackName: String) -> SpotifyPlaylistResult? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = root["id"] as? String, !id.isEmpty
        else { return nil }
        let externalURLs = root["external_urls"] as? [String: Any]
        return SpotifyPlaylistResult(
            id: id,
            name: (root["name"] as? String) ?? fallbackName,
            url: externalURLs?["spotify"] as? String
        )
    }
}
#endif
