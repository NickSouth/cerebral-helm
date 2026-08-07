// Spotify OAuth: PKCE generation + Authorization Code token exchange/refresh (NIC-133).
#if canImport(AppKit)
import CryptoKit
import Foundation
import CerebralCore

/// The OAuth tokens CerebralHelm holds for Spotify (NIC-133). Persisted as a JSON blob in the
/// Keychain by the auth coordinator (Increment 4); the publisher (Increment 7) reads a valid
/// `accessToken` from the session and passes it to the ``SpotifyPlaybackProvider``. `refreshToken`
/// is optional because a refresh response may omit a new one (we keep the previous), and
/// `expiresAt` is the absolute instant the access token stops being valid (derived from the
/// response's `expires_in`), so the session can refresh proactively.
public struct SpotifyTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scope: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
}

/// Builds the authorize URL and performs the Spotify token endpoint exchanges (NIC-133) with an
/// ephemeral `URLSession`. Provider-neutral over the client: the caller supplies the (public)
/// Client ID and the loopback redirect URI. **No client secret is used** — PKCE is the whole
/// reason a native app doesn't need one, and a distributed desktop app couldn't keep it secret.
/// Request building + response parsing are pure `internal static` helpers (unit-tested against the
/// RFC 7636 vector and canned JSON); the async `exchange`/`refresh` wrappers do the network call
/// and are live-smoked once a real authorization round trip exists (Increment 4). A definitive
/// grant rejection (HTTP 400/401, e.g. a revoked refresh token) surfaces as
/// ``SpotifyPlaybackError/notConnected`` ("reconnect"); any other failure is ``providerFailed``.
public struct SpotifyTokenExchange {
    private let session: URLSession
    private let host: String

    /// The scopes the widget needs: read the current playback/track and control it (play/pause/skip
    /// — Increment 8). Supplied to ``authorizeURL(host:clientID:redirectURI:scopes:challenge:state:)``
    /// by the coordinator (Increment 4).
    public static let playbackScopes = [
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-modify-playback-state",
        "user-read-recently-played",
        // Playlist creation (quick-actions phase 4). Both are needed because the private/public
        // choice is the user's at create time, and Spotify scopes those separately — asking for
        // only one would make half the form fail at the API.
        //
        // **Adding these invalidates nothing, but an EXISTING grant does not gain them.** A token
        // issued before this line was written still works for playback and is refused for
        // playlists, so the adapter reports that as "reconnect", not as a broken account.
        "playlist-modify-private",
        "playlist-modify-public",
    ]

    public init(
        session: URLSession? = nil,
        host: String = "https://accounts.spotify.com",
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
    }

    // MARK: - Pure request building / parsing (unit-tested)

    /// The `GET /authorize` URL that opens in the browser to start the flow. The Client ID and
    /// redirect URI are not secret (the Client ID is public; the redirect is a loopback address), so
    /// they ride the query; the secret material is the verifier, which never appears here — only its
    /// SHA-256 `code_challenge` does.
    static func authorizeURL(
        host: String, clientID: String, redirectURI: String, scopes: [String],
        challenge: String, state: String
    ) -> URL? {
        guard var components = URLComponents(string: host + "/authorize") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]
        return components.url
    }

    /// The `POST /api/token` request for the initial `authorization_code` exchange.
    static func makeTokenRequest(
        host: String, code: String, verifier: String, redirectURI: String, clientID: String
    ) -> URLRequest? {
        tokenRequest(host: host, parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    /// The `POST /api/token` request for the `refresh_token` grant.
    static func makeRefreshRequest(host: String, refreshToken: String, clientID: String) -> URLRequest? {
        tokenRequest(host: host, parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private static func tokenRequest(host: String, parameters: [String: String]) -> URLRequest? {
        guard let url = URL(string: host + "/api/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthPKCE.formURLEncoded(parameters)
        return request
    }

    /// Decodes a token response into ``SpotifyTokens``. `expiresAt` is `now + expires_in`. A refresh
    /// response may omit `refresh_token`; when it does we keep `previousRefreshToken` (per Spotify's
    /// docs), so the stored authorization survives a refresh that doesn't rotate the token.
    static func parseTokens(_ data: Data, now: Date, previousRefreshToken: String?) throws -> SpotifyTokens {
        struct Response: Decodable {
            let access_token: String
            let token_type: String?
            let expires_in: Int?
            let refresh_token: String?
            let scope: String?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SpotifyPlaybackError.providerFailed("The token response could not be parsed.")
        }
        let lifetime = TimeInterval(response.expires_in ?? 3600)
        return SpotifyTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(lifetime),
            scope: response.scope
        )
    }

    // MARK: - Network wrappers (live-smoked in Increment 4)

    public func authorizeURL(clientID: String, redirectURI: String, challenge: String, state: String) -> URL? {
        Self.authorizeURL(
            host: host, clientID: clientID, redirectURI: redirectURI,
            scopes: Self.playbackScopes, challenge: challenge, state: state
        )
    }

    public func exchange(
        code: String, verifier: String, redirectURI: String, clientID: String, now: Date = Date()
    ) async throws -> SpotifyTokens {
        guard let request = Self.makeTokenRequest(
            host: host, code: code, verifier: verifier, redirectURI: redirectURI, clientID: clientID
        ) else {
            throw SpotifyPlaybackError.providerFailed("Could not build the token request.")
        }
        return try await send(request, now: now, previousRefreshToken: nil)
    }

    public func refresh(
        refreshToken: String, clientID: String, now: Date = Date()
    ) async throws -> SpotifyTokens {
        guard let request = Self.makeRefreshRequest(
            host: host, refreshToken: refreshToken, clientID: clientID
        ) else {
            throw SpotifyPlaybackError.providerFailed("Could not build the refresh request.")
        }
        return try await send(request, now: now, previousRefreshToken: refreshToken)
    }

    private func send(_ request: URLRequest, now: Date, previousRefreshToken: String?) async throws -> SpotifyTokens {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyPlaybackError.providerFailed("The token service did not return an HTTP response.")
            }
            // A 400/401 is Spotify rejecting the grant (e.g. `invalid_grant` for a revoked or expired
            // refresh token): the stored authorization is dead, so the widget guides the user to
            // reconnect rather than treating it as a transient outage.
            if http.statusCode == 400 || http.statusCode == 401 {
                throw SpotifyPlaybackError.notConnected
            }
            guard (200..<300).contains(http.statusCode) else {
                throw SpotifyPlaybackError.providerFailed("The token service returned an unsuccessful response.")
            }
            return try Self.parseTokens(data, now: now, previousRefreshToken: previousRefreshToken)
        } catch let error as SpotifyPlaybackError {
            throw error
        } catch {
            throw SpotifyPlaybackError.providerFailed(error.localizedDescription)
        }
    }
}

/// The token exchange is the refresh half the ``SpotifyAuthSession`` depends on. Declared here (not
/// beside the session) because a `Sendable`-inheriting conformance must live in the type's own file.
extension SpotifyTokenExchange: SpotifyTokenRefreshing {}
#endif
