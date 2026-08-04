// Spotify OAuth connect: PKCE + a loopback listener + the system browser (NIC-133).
#if canImport(AppKit)
import Foundation
import Network
import CerebralCore
import CerebralTools

/// The result of a successful connect — the granted scope and the access-token expiry. The tokens
/// themselves are persisted to the Keychain, not returned (they never cross back to the UI).
public struct SpotifyConnection: Sendable, Equatable {
    public let scope: String?
    public let expiresAt: Date
}

/// Runs the Spotify Authorization Code + PKCE connect flow on this Mac (NIC-133): generate PKCE,
/// bind a loopback listener, open the system browser to Spotify's consent page, capture the
/// redirected `?code`, exchange it for tokens, and persist them to the Keychain. The redirect URI is
/// a fixed loopback address (`http://127.0.0.1:<port>/callback`) — the user registers exactly this in
/// their Spotify app's allowlist (Spotify permits loopback HTTP). Request parsing / response building
/// / the CSRF-state check are pure static helpers (unit-tested); the full round trip is
/// browser-interactive, so it is verified by the manual OAuth smoke once the connect trigger exists
/// (Increment 6).
public struct SpotifyAuthCoordinator: Sendable {
    private let exchange: SpotifyTokenExchange
    private let secretStore: any SecretStoreManaging
    private let workspace: any WorkspaceOpening
    private let port: UInt16
    private let callbackPath: String
    private let timeout: TimeInterval

    public init(
        exchange: SpotifyTokenExchange = SpotifyTokenExchange(),
        secretStore: any SecretStoreManaging,
        workspace: any WorkspaceOpening = SystemWorkspace(),
        port: UInt16 = 8888,
        callbackPath: String = "/callback",
        timeout: TimeInterval = 180
    ) {
        self.exchange = exchange
        self.secretStore = secretStore
        self.workspace = workspace
        self.port = port
        self.callbackPath = callbackPath
        self.timeout = timeout
    }

    /// The loopback redirect URI the user must register in their Spotify app's allowlist.
    public var redirectURI: String { "http://127.0.0.1:\(port)\(callbackPath)" }

    public func connect(clientID: String, now: Date = Date()) async throws -> SpotifyConnection {
        let verifier = OAuthPKCE.makeVerifier()
        let challenge = OAuthPKCE.challenge(for: verifier)
        let state = OAuthPKCE.makeState()
        guard let authorizeURL = exchange.authorizeURL(
            clientID: clientID, redirectURI: redirectURI, challenge: challenge, state: state
        ) else {
            throw SpotifyPlaybackError.providerFailed("Could not build the Spotify authorize URL.")
        }

        let listener = try LoopbackAuthListener(port: port, responseHTML: Self.successHTML)
        let workspace = self.workspace
        let query: [String: String]
        do {
            query = try await listener.awaitCallback(timeout: timeout) { _ in
                // The bound port is the fixed registered one, so `authorizeURL`'s redirect already
                // matches. Open the browser only once the listener is accepting, so the redirect
                // cannot race the bind.
                Task { try? await workspace.openURL(authorizeURL) }
            }
        } catch let error as LoopbackAuthError {
            // The shared listener is provider-neutral; the message the user sees is not.
            throw SpotifyPlaybackError.providerFailed(Self.describe(error))
        }

        let code = try Self.authorizationCode(fromQuery: query, expectedState: state).get()
        let tokens = try await exchange.exchange(
            code: code, verifier: verifier, redirectURI: redirectURI, clientID: clientID, now: now
        )
        try await SpotifyTokenBlob.save(tokens, to: secretStore)
        return SpotifyConnection(scope: tokens.scope, expiresAt: tokens.expiresAt)
    }

    /// Removes the stored authorization (the "disconnect" path, Increment 6). Missing tokens are not
    /// an error — disconnecting an already-disconnected account is a no-op success.
    public func disconnect() async throws {
        do {
            try await secretStore.delete(reference: SpotifyTokenBlob.reference)
        } catch {
            // Already absent — nothing to remove.
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// The query params of an HTTP request line like `GET /callback?code=abc&state=xyz HTTP/1.1`.
    /// Parsing moved to the shared listener; this forwards so the behaviour stays covered here too.
    static func query(fromRequestLine line: String) -> [String: String] {
        LoopbackAuthListener.query(fromRequestLine: line)
    }

    /// Spotify's wording for a provider-neutral listener failure.
    static func describe(_ error: LoopbackAuthError) -> String {
        switch error {
        case let .bindFailed(detail): return "The loopback listener failed: \(detail)"
        case .timedOut: return "Timed out waiting for the Spotify authorization callback."
        case .closedEarly: return "The authorization callback closed before a request was received."
        }
    }

    /// Validates the callback and extracts the authorization code. An `error` param (e.g. the user
    /// declined) fails; a mismatched `state` fails the CSRF check; a missing code fails. The failure
    /// diagnostic is coarse and never surfaced verbatim (the widget shows a generic message).
    static func authorizationCode(
        fromQuery query: [String: String], expectedState: String
    ) -> Result<String, SpotifyPlaybackError> {
        if let error = query["error"] {
            return .failure(.providerFailed("Spotify authorization was not granted (\(error))."))
        }
        guard query["state"] == expectedState else {
            return .failure(.providerFailed("The authorization response failed the CSRF state check."))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .failure(.providerFailed("The authorization response contained no code."))
        }
        return .success(code)
    }

    /// A minimal HTTP/1.1 response wrapping `html`. Forwards to the shared listener.
    static func httpResponse(html: String) -> Data {
        LoopbackAuthListener.httpResponse(html: html)
    }

    /// The page the browser shows after the redirect is captured.
    static let successHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>CerebralHelm</title></head>\
    <body style="font-family:-apple-system,system-ui,sans-serif;text-align:center;padding-top:4rem;color:#111">\
    <h2>Spotify connected</h2><p>You can close this tab and return to CerebralHelm.</p></body></html>
    """
}
#endif
