// Gmail integration: Google's OAuth request building, parsing, and the refresh session.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

/// The pure halves of the Google OAuth layer. The interesting assertions are the ones that catch a
/// **connection that looks fine and dies in an hour** — a missing `access_type=offline`, a dropped
/// refresh token — because that failure mode is invisible at connect time.

private func query(_ url: URL) -> [String: String] {
    var found: [String: String] = [:]
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
        found[item.name] = item.value
    }
    return found
}

private func body(_ request: URLRequest) -> [String: String] {
    var found: [String: String] = [:]
    for pair in String(decoding: request.httpBody ?? Data(), as: UTF8.self).split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            found[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
    }
    return found
}

// MARK: - Authorize URL

@Test("the authorize URL asks for a refresh token in the only way that reliably returns one")
func googleAuthorizeURLRequestsOfflineAccess() throws {
    let url = try #require(GoogleTokenExchange.authorizeURL(
        host: "https://accounts.google.com",
        clientID: "client-123.apps.googleusercontent.com",
        redirectURI: "http://127.0.0.1:8899/callback",
        scopes: GoogleTokenExchange.gmailScopes,
        challenge: "chal", state: "state-1"
    ))
    let items = query(url)

    #expect(url.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
    // The pair that matters: without BOTH, re-authorizing an already-granted account returns an
    // access token and no refresh token — a connection that looks successful and dies in an hour.
    #expect(items["access_type"] == "offline")
    #expect(items["prompt"] == "consent")
    #expect(items["code_challenge_method"] == "S256")
    #expect(items["code_challenge"] == "chal")
    #expect(items["state"] == "state-1")
    #expect(items["scope"] == "https://www.googleapis.com/auth/gmail.readonly")
    // The verifier is the secret and must never appear in a URL that opens in a browser.
    #expect(!url.absoluteString.contains("code_verifier"))
}

@Test("the authorize URL carries no client secret — PKCE is why one isn't needed")
func googleAuthorizeURLCarriesNoSecret() throws {
    let url = try #require(GoogleTokenExchange.authorizeURL(
        host: "https://accounts.google.com", clientID: "c", redirectURI: "http://127.0.0.1:1/callback",
        scopes: ["s"], challenge: "chal", state: "st"
    ))
    #expect(!url.absoluteString.contains("client_secret"))
}

// MARK: - Token requests

@Test("the code exchange sends the verifier and the redirect; the refresh sends neither")
func googleTokenRequestsCarryTheRightParameters() throws {
    let exchange = try #require(GoogleTokenExchange.makeTokenRequest(
        host: "https://oauth2.googleapis.com", code: "auth-code", verifier: "verifier-1",
        redirectURI: "http://127.0.0.1:8899/callback", clientID: "client-1", clientSecret: nil
    ))
    #expect(exchange.url?.absoluteString == "https://oauth2.googleapis.com/token")
    #expect(exchange.httpMethod == "POST")
    let exchangeBody = body(exchange)
    #expect(exchangeBody["grant_type"] == "authorization_code")
    #expect(exchangeBody["code_verifier"] == "verifier-1")
    #expect(exchangeBody["redirect_uri"] == "http://127.0.0.1:8899/callback")
    #expect(exchangeBody["client_secret"] == nil)

    let refresh = try #require(GoogleTokenExchange.makeRefreshRequest(
        host: "https://oauth2.googleapis.com", refreshToken: "refresh-1", clientID: "client-1",
        clientSecret: nil
    ))
    let refreshBody = body(refresh)
    #expect(refreshBody["grant_type"] == "refresh_token")
    #expect(refreshBody["refresh_token"] == "refresh-1")
    // Google's refresh grant does not take a redirect_uri, and rejects the request if one is sent.
    #expect(refreshBody["redirect_uri"] == nil)
}

// MARK: - Parsing

@Test("a refresh response with no refresh_token keeps the one we already hold")
func googleParseTokensCarriesTheRefreshTokenForward() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    // Google omits `refresh_token` on every refresh. Dropping it would make each refresh the last.
    let refreshed = try GoogleTokenExchange.parseTokens(
        Data(#"{"access_token":"new-access","expires_in":3599,"scope":"gmail.readonly"}"#.utf8),
        now: now, previousRefreshToken: "kept-refresh"
    )
    #expect(refreshed.accessToken == "new-access")
    #expect(refreshed.refreshToken == "kept-refresh")
    #expect(refreshed.expiresAt == now.addingTimeInterval(3599))

    // The initial exchange does carry one, and it wins.
    let initial = try GoogleTokenExchange.parseTokens(
        Data(#"{"access_token":"a","refresh_token":"fresh","expires_in":60}"#.utf8),
        now: now, previousRefreshToken: nil
    )
    #expect(initial.refreshToken == "fresh")
}

@Test("an unparseable token response fails rather than yielding an empty grant")
func googleParseTokensRejectsGarbage() {
    #expect(throws: GoogleAuthError.self) {
        _ = try GoogleTokenExchange.parseTokens(Data("not json".utf8), now: Date(), previousRefreshToken: nil)
    }
}

@Test("a Desktop client sends its secret — the exemption covers Android/iOS/Chrome, not Desktop")
func googleTokenRequestsCarryTheClientSecret() throws {
    // Google's table calls `client_secret` optional, but its own note scopes that to Android, iOS
    // and Chrome clients. A Desktop client is issued one and the token endpoint requires it;
    // omitting it fails the exchange with `invalid_client` — the bug this test exists to prevent.
    let exchange = try #require(GoogleTokenExchange.makeTokenRequest(
        host: "https://oauth2.googleapis.com", code: "c", verifier: "v",
        redirectURI: "http://127.0.0.1:8890/callback", clientID: "id", clientSecret: "secret-1"
    ))
    #expect(body(exchange)["client_secret"] == "secret-1")

    let refresh = try #require(GoogleTokenExchange.makeRefreshRequest(
        host: "https://oauth2.googleapis.com", refreshToken: "r", clientID: "id", clientSecret: "secret-1"
    ))
    #expect(body(refresh)["client_secret"] == "secret-1")

    // A client type that genuinely has no secret must still work, so an empty one is not sent.
    let none = try #require(GoogleTokenExchange.makeTokenRequest(
        host: "https://oauth2.googleapis.com", code: "c", verifier: "v",
        redirectURI: "http://127.0.0.1:8890/callback", clientID: "id", clientSecret: ""
    ))
    #expect(body(none)["client_secret"] == nil)
}

@Test("the same 400 means different things on a refresh and on a first exchange")
func googleAuthErrorDependsOnWhichGrant() {
    // On a REFRESH, 400 is the lapsed grant — the 7-day expiry or a password change — and
    // Reconnect really is the fix.
    #expect(GoogleTokenExchange.authError(for: 400, body: Data(), grant: .refresh) == .notConnected)
    #expect(GoogleTokenExchange.authError(for: 401, body: Data(), grant: .refresh) == .notConnected)

    // On the INITIAL exchange the grant is seconds old, so it cannot have expired: the request was
    // wrong. Telling the user to reconnect would send them round the identical loop forever, which
    // is exactly what happened before this distinction existed.
    let rejected = GoogleTokenExchange.authError(
        for: 401,
        body: Data(#"{"error":"invalid_client","error_description":"Unauthorized"}"#.utf8),
        grant: .exchange
    )
    guard case let .providerFailed(detail) = rejected else {
        Issue.record("a rejected first exchange is a configuration fault, not a lapsed grant")
        return
    }
    // Google's own words, because they name the actual problem.
    #expect(detail.contains("invalid_client"))
    #expect(detail.contains("Unauthorized"))

    #expect(GoogleTokenExchange.authError(for: 200, body: Data(), grant: .exchange) == nil)
    guard case .providerFailed = GoogleTokenExchange.authError(
        for: 503, body: Data("down".utf8), grant: .refresh
    ) else {
        Issue.record("a server fault is not a lapsed grant — the remedies differ")
        return
    }
}

// MARK: - The session

/// A store that records writes, so "the refreshed token was persisted" is provable.
private final class FakeSecrets: SecretStoreManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(_ values: [String: String]) { self.values = values }

    func store(reference: String, value: String) async throws { put(reference, value) }
    func delete(reference: String) async throws { put(reference, nil) }
    func readValue(reference: String) async throws -> String {
        guard let value = snapshot()[reference] else { throw NativeCapabilityError.notFound(reference) }
        return value
    }

    private func put(_ key: String, _ value: String?) {
        lock.lock(); defer { lock.unlock() }
        if let value { values[key] = value } else { values.removeValue(forKey: key) }
    }
    func snapshot() -> [String: String] { lock.lock(); defer { lock.unlock() }; return values }
}

private struct FakeRefresher: GoogleTokenRefreshing {
    let result: Result<GoogleTokens, GoogleAuthError>
    func refresh(
        refreshToken: String, clientID: String, clientSecret: String?, now: Date
    ) async throws -> GoogleTokens {
        try result.get()
    }
}

private func blob(_ tokens: GoogleTokens) throws -> String { try GoogleTokenBlob.encode(tokens) }

private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

@Test("no stored grant is 'not connected' — the state a first run and a lapsed grant share")
func googleSessionReportsMissingGrant() async {
    let session = GoogleAuthSession(
        secretStore: FakeSecrets([:]),
        refresher: FakeRefresher(result: .failure(.notConnected))
    )
    await #expect(throws: GoogleAuthError.notConnected) { _ = try await session.accessToken(now: anchor) }
    #expect(await session.isConnected() == false)
}

@Test("a live token is returned without touching the network")
func googleSessionUsesALiveToken() async throws {
    let tokens = GoogleTokens(
        accessToken: "live", refreshToken: "r", expiresAt: anchor.addingTimeInterval(3600), scope: nil
    )
    let session = GoogleAuthSession(
        secretStore: FakeSecrets([GoogleTokenBlob.reference: try blob(tokens)]),
        // A refresher that would fail if it were reached at all.
        refresher: FakeRefresher(result: .failure(.providerFailed("must not refresh")))
    )
    #expect(try await session.accessToken(now: anchor) == "live")
}

@Test("a token at the margin refreshes, and the new one is persisted")
func googleSessionRefreshesNearExpiry() async throws {
    let store = FakeSecrets([
        GoogleTokenBlob.reference: try blob(GoogleTokens(
            accessToken: "stale", refreshToken: "r", expiresAt: anchor.addingTimeInterval(30), scope: nil
        )),
        GoogleAuthSession.clientIDReference: "client-1"
    ])
    let refreshed = GoogleTokens(
        accessToken: "fresh", refreshToken: "r", expiresAt: anchor.addingTimeInterval(3600), scope: nil
    )
    let session = GoogleAuthSession(secretStore: store, refresher: FakeRefresher(result: .success(refreshed)))

    #expect(try await session.accessToken(now: anchor) == "fresh")
    // Persisted, not just cached: a relaunch a minute later must not have to refresh again.
    // Split deliberately: `#require` cannot nest inside another `#require`.
    let json = try #require(store.snapshot()[GoogleTokenBlob.reference])
    let stored = try #require(GoogleTokenBlob.decode(json))
    #expect(stored.accessToken == "fresh")
}

@Test("a refresh with no Client ID is reported as unconfigured, not as a broken account")
func googleSessionNeedsAClientID() async throws {
    let store = FakeSecrets([
        GoogleTokenBlob.reference: try blob(GoogleTokens(
            accessToken: "stale", refreshToken: "r", expiresAt: anchor.addingTimeInterval(1), scope: nil
        ))
    ])
    let session = GoogleAuthSession(
        secretStore: store, refresher: FakeRefresher(result: .failure(.providerFailed("unreached")))
    )
    await #expect(throws: GoogleAuthError.clientIDMissing) { _ = try await session.accessToken(now: anchor) }
}

@Test("a stored grant with no refresh token cannot be renewed and says reconnect")
func googleSessionRefusesAGrantItCannotRenew() async throws {
    // The failure `access_type=offline` + `prompt=consent` exist to prevent, caught here rather
    // than as a mystery an hour after connecting.
    let store = FakeSecrets([
        GoogleTokenBlob.reference: try blob(GoogleTokens(
            accessToken: "stale", refreshToken: nil, expiresAt: anchor.addingTimeInterval(1), scope: nil
        )),
        GoogleAuthSession.clientIDReference: "client-1"
    ])
    let session = GoogleAuthSession(
        secretStore: store, refresher: FakeRefresher(result: .failure(.providerFailed("unreached")))
    )
    await #expect(throws: GoogleAuthError.notConnected) { _ = try await session.accessToken(now: anchor) }
}

@Test("invalidate drops the cached token, so Disconnect actually disconnects")
func googleSessionInvalidatesItsCache() async throws {
    let store = FakeSecrets([
        GoogleTokenBlob.reference: try blob(GoogleTokens(
            accessToken: "live", refreshToken: "r", expiresAt: anchor.addingTimeInterval(3600), scope: nil
        ))
    ])
    let session = GoogleAuthSession(
        secretStore: store, refresher: FakeRefresher(result: .failure(.notConnected))
    )
    #expect(try await session.accessToken(now: anchor) == "live")

    try await store.delete(reference: GoogleTokenBlob.reference)
    await session.invalidate()
    // Without invalidate the session would keep serving a token the user just revoked.
    await #expect(throws: GoogleAuthError.notConnected) { _ = try await session.accessToken(now: anchor) }
}
#endif

// MARK: - The coordinator's callback handling

@Test("the CSRF state check refuses a callback this process did not start")
func googleCoordinatorChecksState() {
    // A callback carrying a perfectly usable code is still refused when it did not originate from
    // the authorize request this process began — that is the whole point of `state`.
    let wrongState = GoogleAuthCoordinator.authorizationCode(
        fromQuery: ["code": "usable-code", "state": "someone-elses"], expectedState: "ours"
    )
    guard case .failure = wrongState else {
        Issue.record("a mismatched state must never yield a code")
        return
    }
    // The matching case does.
    let right = GoogleAuthCoordinator.authorizationCode(
        fromQuery: ["code": "usable-code", "state": "ours"], expectedState: "ours"
    )
    #expect((try? right.get()) == "usable-code")
}

@Test("a declined consent is cancelled, not a failure — they are different events")
func googleCoordinatorSeparatesDeclineFromFault() {
    // `access_denied` is "the user said no", or an account that is not a listed test user of a
    // Testing-mode project. Neither deserves an error surface.
    let declined = GoogleAuthCoordinator.authorizationCode(
        fromQuery: ["error": "access_denied"], expectedState: "ours"
    )
    guard case let .failure(error) = declined, error == .cancelled else {
        Issue.record("a declined consent is a cancellation")
        return
    }
    // Anything else Google reports is a real fault and says so.
    let broken = GoogleAuthCoordinator.authorizationCode(
        fromQuery: ["error": "invalid_scope"], expectedState: "ours"
    )
    guard case let .failure(other) = broken, case .providerFailed = other else {
        Issue.record("an unexpected error is not a cancellation")
        return
    }
}

@Test("a missing code fails rather than proceeding to an exchange that cannot work")
func googleCoordinatorRequiresACode() {
    let empty = GoogleAuthCoordinator.authorizationCode(
        fromQuery: ["state": "ours"], expectedState: "ours"
    )
    guard case .failure = empty else {
        Issue.record("no code is not a success")
        return
    }
}

@Test("a listener timeout reads as cancelled — the user simply never finished")
func googleCoordinatorMapsListenerFailures() {
    #expect(GoogleAuthCoordinator.authError(for: .timedOut("x")) == .cancelled)
    guard case .providerFailed = GoogleAuthCoordinator.authError(for: .bindFailed("port busy")) else {
        Issue.record("a failed bind is a real fault")
        return
    }
    guard case .providerFailed = GoogleAuthCoordinator.authError(for: .closedEarly) else {
        Issue.record("a truncated callback is a real fault")
        return
    }
}

@Test("the redirect URI is the fixed loopback address, on a port nothing else here uses")
func googleCoordinatorUsesItsOwnPort() {
    let coordinator = GoogleAuthCoordinator(secretStore: FakeSecrets([:]))
    // Fixed rather than ephemeral because Google's native-app doc says the redirect must match a
    // configured URI exactly. 8890 avoids Spotify's 8888 and the Canvas ingest server's 8899.
    #expect(coordinator.redirectURI == "http://127.0.0.1:8890/callback")
}
