// NIC-133 Increment 3: PKCE generation + Spotify token request building and response parsing.
// The pure static helpers are unit-tested here (incl. the RFC 7636 vector); the async
// exchange/refresh wrappers do the network call and are live-smoked once a real authorization
// round trip exists (Increment 4).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the PKCE challenge matches the RFC 7636 Appendix B test vector")
func spotifyPKCEChallengeVector() {
    // RFC 7636 Appendix B: this exact verifier must produce this exact S256 challenge.
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    #expect(OAuthPKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test("a generated verifier is RFC-length and uses only unreserved characters")
func spotifyPKCEVerifierShape() {
    let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    // Two draws differ (high entropy) and both satisfy the RFC constraints.
    let a = OAuthPKCE.makeVerifier()
    let b = OAuthPKCE.makeVerifier()
    #expect(a != b)
    for verifier in [a, b] {
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy { unreserved.contains($0) })
    }
}

@Test("the authorize URL carries PKCE (S256 + challenge) and never the verifier or a secret")
func spotifyAuthorizeURL() throws {
    let url = try #require(SpotifyTokenExchange.authorizeURL(
        host: "https://accounts.spotify.com", clientID: "client-abc",
        redirectURI: "http://127.0.0.1:8080/callback",
        scopes: ["user-read-currently-playing", "user-modify-playback-state"],
        challenge: "CHALLENGE123", state: "state-xyz"
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "accounts.spotify.com")
    #expect(components.path == "/authorize")
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
    #expect(items["response_type"] == "code")
    #expect(items["client_id"] == "client-abc")
    #expect(items["redirect_uri"] == "http://127.0.0.1:8080/callback")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["code_challenge"] == "CHALLENGE123")
    #expect(items["state"] == "state-xyz")
    #expect(items["scope"] == "user-read-currently-playing user-modify-playback-state")
    // The verifier is never sent to the authorize endpoint — only its challenge is.
    #expect(!url.absoluteString.contains("code_verifier"))
}

@Test("the authorize URL requests exactly the scopes the built surfaces need, and no more")
func spotifyPlaybackScopes() {
    // Exact, not a superset check: an over-broad scope request is a real fault, and this is the
    // one place it would be caught. The playlist pair arrived with `create-playlist`
    // (quick-actions phase 4) — a grant made before them keeps working for playback and is
    // refused for playlists, which the adapter reports as "reconnect".
    #expect(SpotifyTokenExchange.playbackScopes == [
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-modify-playback-state",
        "user-read-recently-played",
        "playlist-modify-private",
        "playlist-modify-public",
    ])
}

@Test("the code-exchange request is a form POST to /api/token carrying the verifier, no secret")
func spotifyTokenRequest() throws {
    let request = try #require(SpotifyTokenExchange.makeTokenRequest(
        host: "https://accounts.spotify.com", code: "auth-code-1", verifier: "verifier-1",
        redirectURI: "http://127.0.0.1:8080/callback", clientID: "client-abc"
    ))
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://accounts.spotify.com/api/token")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains("grant_type=authorization_code"))
    #expect(body.contains("code=auth-code-1"))
    #expect(body.contains("code_verifier=verifier-1"))
    #expect(body.contains("client_id=client-abc"))
    // PKCE means no client secret is ever sent.
    #expect(!body.contains("client_secret"))
    // The loopback redirect URI is form-encoded (reserved chars escaped).
    #expect(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Fcallback"))
}

@Test("the refresh request is a form POST with the refresh_token grant and no secret")
func spotifyRefreshRequest() throws {
    let request = try #require(SpotifyTokenExchange.makeRefreshRequest(
        host: "https://accounts.spotify.com", refreshToken: "refresh-1", clientID: "client-abc"
    ))
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains("grant_type=refresh_token"))
    #expect(body.contains("refresh_token=refresh-1"))
    #expect(body.contains("client_id=client-abc"))
    #expect(!body.contains("client_secret"))
}

@Test("a token response parses into tokens with an absolute expiry derived from expires_in")
func spotifyParseTokens() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let json = Data("""
    { "access_token": "at-123", "token_type": "Bearer", "expires_in": 3600,
      "refresh_token": "rt-456", "scope": "user-read-currently-playing" }
    """.utf8)

    let tokens = try SpotifyTokenExchange.parseTokens(json, now: now, previousRefreshToken: nil)
    #expect(tokens.accessToken == "at-123")
    #expect(tokens.refreshToken == "rt-456")
    #expect(tokens.scope == "user-read-currently-playing")
    #expect(tokens.expiresAt == now.addingTimeInterval(3600))
}

@Test("a refresh response with no new refresh_token keeps the previous one")
func spotifyParseTokensKeepsPreviousRefresh() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Spotify often omits refresh_token on a refresh — the stored authorization must survive.
    let json = Data("""
    { "access_token": "at-new", "token_type": "Bearer", "expires_in": 3600 }
    """.utf8)

    let tokens = try SpotifyTokenExchange.parseTokens(json, now: now, previousRefreshToken: "rt-original")
    #expect(tokens.accessToken == "at-new")
    #expect(tokens.refreshToken == "rt-original")
}

@Test("a malformed token response throws providerFailed, never a fabricated token")
func spotifyParseTokensFailure() {
    #expect(throws: SpotifyPlaybackError.self) {
        _ = try SpotifyTokenExchange.parseTokens(Data("not json".utf8), now: Date(), previousRefreshToken: nil)
    }
}
#endif
