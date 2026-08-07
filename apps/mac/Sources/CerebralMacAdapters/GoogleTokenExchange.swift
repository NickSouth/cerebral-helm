// Google OAuth: authorize URL + token exchange/refresh for the Gmail integration.
#if canImport(AppKit)
import Foundation
import CerebralCore

/// What went wrong reaching Google. Separated from the Gmail *reading* errors: this is about the
/// grant, and every case here has a different remedy from "the inbox could not be read".
public enum GoogleAuthError: Error, Equatable, Sendable {
    /// No Client ID stored yet — the user has not set the integration up.
    case clientIDMissing
    /// No stored grant, or one Google has definitively rejected. The remedy is Reconnect.
    ///
    /// **This is the expected steady state on an unverified app in "Testing" publishing status**,
    /// where Google expires refresh tokens after 7 days — and it also fires when the user changes
    /// their Google password, which revokes Gmail grants outright. The surface must therefore
    /// treat "reconnect" as ordinary, not as an error worth alarming about.
    case notConnected
    /// The user closed the browser, denied consent, or the callback never arrived.
    case cancelled
    case providerFailed(String)
}

/// The tokens held for Google, persisted as one Keychain blob.
public struct GoogleTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scope: String?
    /// The connected account's own address, learned once at connect from `users.getProfile`.
    ///
    /// It is what a Gmail link is addressed to (`/mail/u/<address>/`) and what resolves the Chrome
    /// profile to open it in, so it lives with the grant it describes rather than in a setting the
    /// user would have to keep in step with which account they connected.
    ///
    /// Optional, and absent in blobs written before it existed — an older stored grant keeps
    /// working and simply falls back to the default-account URL.
    public let address: String?

    public init(
        accessToken: String, refreshToken: String?, expiresAt: Date, scope: String?,
        address: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.address = address
    }

    /// The same grant, tagged with the account it belongs to. Used at connect (where the address is
    /// fetched) and at **refresh** — Google's refresh response carries no address, so without this
    /// the first renewal would quietly drop it and links would fall back to the default account.
    public func withAddress(_ address: String?) -> GoogleTokens {
        GoogleTokens(
            accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt,
            scope: scope, address: address ?? self.address
        )
    }
}

/// Builds Google's authorize URL and performs its token exchanges.
///
/// Verified against Google's installed-app documentation (2026-08-04):
///
/// - Authorization endpoint `https://accounts.google.com/o/oauth2/v2/auth`, token endpoint
///   `https://oauth2.googleapis.com/token` — **different hosts**, unlike Spotify's single one.
/// - PKCE is used, and a Desktop client's `client_secret` **is** sent alongside it when one is
///   stored. Google's parameter table calls the secret "Optional", but its note scopes that
///   exemption to Android/iOS/Chrome clients — a Desktop client is issued one and the token
///   endpoint rejects the exchange without it. See ``makeTokenRequest``.
/// - Refresh tokens "are always returned for installed applications" — but only when the consent
///   screen is actually shown, which is why `access_type=offline` and `prompt=consent` are both
///   sent. Without them a *re-*authorization returns an access token and no refresh token, and the
///   connection silently becomes one that dies in an hour.
public struct GoogleTokenExchange {
    /// Read-only Gmail (owner decision, 2026-08-04). This is a **restricted** scope: Google wants a
    /// verification review and a security assessment before an app using it is published, and an
    /// app left in "Testing" has its refresh tokens expired every 7 days. That is a project setting
    /// rather than anything this code can influence — so the adapter's job is to fail *honestly*
    /// when the grant lapses, which it does through ``GoogleAuthError/notConnected``.
    ///
    /// The unread count needs none of this — `labels.get` is satisfied by the non-sensitive
    /// `gmail.labels` scope — but readonly covers it too, and asking for both in one grant would
    /// not make the count survive any longer: combining a non-sensitive scope with a restricted one
    /// makes the whole grant restricted.
    public static let gmailScopes = ["https://www.googleapis.com/auth/gmail.readonly"]

    private let session: URLSession
    private let authorizeHost: String
    private let tokenHost: String

    public init(
        session: URLSession? = nil,
        authorizeHost: String = "https://accounts.google.com",
        tokenHost: String = "https://oauth2.googleapis.com",
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
        self.authorizeHost = authorizeHost
        self.tokenHost = tokenHost
    }

    // MARK: - Pure request building / parsing (unit-tested)

    /// The URL that opens in the browser to start the flow.
    ///
    /// `access_type=offline` asks for a refresh token; `prompt=consent` forces the consent screen
    /// even on a re-authorization, which is what guarantees one actually comes back. Without the
    /// pair, reconnecting an already-granted account yields an access token that expires in an hour
    /// and nothing to renew it with — a failure that looks like success until the hour is up.
    static func authorizeURL(
        host: String, clientID: String, redirectURI: String, scopes: [String],
        challenge: String, state: String
    ) -> URL? {
        guard var components = URLComponents(string: host + "/o/oauth2/v2/auth") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url
    }

    static func makeTokenRequest(
        host: String, code: String, verifier: String, redirectURI: String,
        clientID: String, clientSecret: String?
    ) -> URLRequest? {
        var parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        // Google's parameter table calls `client_secret` "Optional", but its own note scopes that:
        // "not applicable to requests from clients registered as Android, iOS, or Chrome
        // applications". **Desktop is not on that list** — a Desktop client is issued a secret and
        // the token endpoint expects it, so omitting it fails the exchange with `invalid_client`.
        // Sent only when one is stored, so a genuinely public client still works.
        if let clientSecret, !clientSecret.isEmpty {
            parameters["client_secret"] = clientSecret
        }
        return tokenRequest(host: host, parameters: parameters)
    }

    /// The refresh grant. It deliberately carries **no** `redirect_uri` — Google's refresh request
    /// does not take one, and sending it is rejected.
    static func makeRefreshRequest(
        host: String, refreshToken: String, clientID: String, clientSecret: String?
    ) -> URLRequest? {
        var parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        if let clientSecret, !clientSecret.isEmpty {
            parameters["client_secret"] = clientSecret
        }
        return tokenRequest(host: host, parameters: parameters)
    }

    private static func tokenRequest(host: String, parameters: [String: String]) -> URLRequest? {
        guard let url = URL(string: host + "/token") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthPKCE.formURLEncoded(parameters)
        return request
    }

    /// Decodes a token response. A **refresh** response never carries a `refresh_token`, so the
    /// previous one is carried forward — dropping it would turn every refresh into the last one.
    static func parseTokens(_ data: Data, now: Date, previousRefreshToken: String?) throws -> GoogleTokens {
        struct Response: Decodable {
            let access_token: String
            let expires_in: Int?
            let refresh_token: String?
            let scope: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GoogleAuthError.providerFailed("The token response could not be parsed.")
        }
        return GoogleTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? previousRefreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
            scope: response.scope
        )
    }

    /// Which grant a response is answering. The **same status code means different things** at the
    /// two call sites, and collapsing them was a real bug: a fresh authorization that comes back
    /// `400` was rejected because the *request* was wrong, and telling the user to "reconnect"
    /// sends them round the identical loop forever with no new information.
    enum Grant {
        case exchange
        case refresh
    }

    /// Maps a token-endpoint status onto the error the surface acts on.
    ///
    /// On a **refresh**, `400`/`401` is the lapsed grant — the Testing-mode 7-day expiry, or a
    /// Google password change — and the remedy really is Reconnect.
    ///
    /// On the **initial exchange** the grant is seconds old, so the same status cannot mean
    /// "expired". It means the request was malformed or the client is misconfigured (a missing
    /// `client_secret` for a Desktop client answers `invalid_client` here), and Google says which
    /// in the body. That detail is surfaced verbatim: it is the only thing that distinguishes one
    /// configuration mistake from another.
    static func authError(for statusCode: Int, body: Data, grant: Grant) -> GoogleAuthError? {
        guard !(200..<300).contains(statusCode) else { return nil }
        if grant == .refresh, statusCode == 400 || statusCode == 401 {
            return .notConnected
        }
        return .providerFailed(describe(statusCode: statusCode, body: body))
    }

    /// Google's own words where it gives them. Its token endpoint answers failures with
    /// `{"error": "...", "error_description": "..."}`, which names the actual problem far better
    /// than any message written here could.
    static func describe(statusCode: Int, body: Data) -> String {
        struct Failure: Decodable {
            let error: String?
            let error_description: String?
        }
        if let failure = try? JSONDecoder().decode(Failure.self, from: body),
           let code = failure.error {
            let detail = failure.error_description.map { ": \($0)" } ?? ""
            return "Google rejected the request (\(code)\(detail))."
        }
        let raw = String(data: body, encoding: .utf8) ?? ""
        return raw.isEmpty
            ? "Google returned HTTP \(statusCode)."
            : "Google returned HTTP \(statusCode): \(raw)"
    }

    // MARK: - Network wrappers

    public func authorizeURL(
        clientID: String, redirectURI: String, challenge: String, state: String
    ) -> URL? {
        Self.authorizeURL(
            host: authorizeHost, clientID: clientID, redirectURI: redirectURI,
            scopes: Self.gmailScopes, challenge: challenge, state: state
        )
    }

    public func exchange(
        code: String, verifier: String, redirectURI: String,
        clientID: String, clientSecret: String?, now: Date = Date()
    ) async throws -> GoogleTokens {
        guard let request = Self.makeTokenRequest(
            host: tokenHost, code: code, verifier: verifier, redirectURI: redirectURI,
            clientID: clientID, clientSecret: clientSecret
        ) else {
            throw GoogleAuthError.providerFailed("Could not build the token request.")
        }
        return try await send(request, now: now, previousRefreshToken: nil, grant: .exchange)
    }

    public func refresh(
        refreshToken: String, clientID: String, clientSecret: String?, now: Date = Date()
    ) async throws -> GoogleTokens {
        guard let request = Self.makeRefreshRequest(
            host: tokenHost, refreshToken: refreshToken, clientID: clientID, clientSecret: clientSecret
        ) else {
            throw GoogleAuthError.providerFailed("Could not build the refresh request.")
        }
        return try await send(request, now: now, previousRefreshToken: refreshToken, grant: .refresh)
    }

    private func send(
        _ request: URLRequest, now: Date, previousRefreshToken: String?, grant: Grant
    ) async throws -> GoogleTokens {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw GoogleAuthError.cancelled
        } catch {
            throw GoogleAuthError.providerFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse,
           let error = Self.authError(for: http.statusCode, body: data, grant: grant) {
            throw error
        }
        return try Self.parseTokens(data, now: now, previousRefreshToken: previousRefreshToken)
    }
}

/// Declared here rather than beside the protocol: a `Sendable`-inheriting conformance must live in
/// the same file as the type (the same constraint `SpotifyTokenExchange` documents).
extension GoogleTokenExchange: GoogleTokenRefreshing {}
#endif
