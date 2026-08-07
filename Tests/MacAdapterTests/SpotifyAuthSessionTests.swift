// NIC-133 Increment 4: the session that reads stored Spotify tokens and refreshes near expiry.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralTools
@testable import CerebralMacAdapters

private let spotifyNow = Date(timeIntervalSince1970: 1_700_000_000)

private func spotifyStoredTokens(
    access: String, refresh: String?, expiresIn: TimeInterval, scope: String? = "user-read-currently-playing"
) -> SpotifyTokens {
    SpotifyTokens(
        accessToken: access, refreshToken: refresh,
        expiresAt: spotifyNow.addingTimeInterval(expiresIn), scope: scope
    )
}

/// A fake refresh half that records calls and returns a fixed outcome — so the session's refresh
/// path is unit-tested without a network round trip.
private actor SpotifyFakeRefresher: SpotifyTokenRefreshing {
    private(set) var calls = 0
    private let outcome: Result<SpotifyTokens, SpotifyPlaybackError>

    init(_ outcome: Result<SpotifyTokens, SpotifyPlaybackError>) { self.outcome = outcome }

    func refresh(refreshToken: String, clientID: String, now: Date) async throws -> SpotifyTokens {
        calls += 1
        return try outcome.get()
    }
}

private func makeStore(_ tokens: SpotifyTokens?, clientID: String? = "client-abc") throws -> MockSecretStore {
    var values: [String: String] = [:]
    if let tokens { values[SpotifyTokenBlob.reference] = try SpotifyTokenBlob.encode(tokens) }
    if let clientID { values["spotify_client_id"] = clientID }
    return MockSecretStore(values: values)
}

@Test("a still-valid access token is returned as-is, without refreshing")
func spotifySessionReturnsValidToken() async throws {
    let store = try makeStore(spotifyStoredTokens(access: "at-valid", refresh: "rt", expiresIn: 3600))
    let refresher = SpotifyFakeRefresher(.failure(.providerFailed("must not be called")))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    let token = try await session.accessToken(now: spotifyNow)
    #expect(token == "at-valid")
    #expect(await refresher.calls == 0)
}

@Test("a token at/near expiry is refreshed with the stored Client ID; a rotated refresh token is persisted")
func spotifySessionRefreshesNearExpiry() async throws {
    // Expires in 30s — inside the 60s refresh margin.
    let store = try makeStore(spotifyStoredTokens(access: "at-old", refresh: "rt-old", expiresIn: 30))
    let refreshed = spotifyStoredTokens(access: "at-new", refresh: "rt-new", expiresIn: 3600)
    let refresher = SpotifyFakeRefresher(.success(refreshed))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    let token = try await session.accessToken(now: spotifyNow)
    #expect(token == "at-new")
    #expect(await refresher.calls == 1)

    // The refresh token rotated, so the grant was written back — dropping a rotated refresh token
    // would end the connection permanently.
    let reloaded = try await SpotifyTokenBlob.load(from: store)
    #expect(reloaded?.accessToken == "at-new")
    #expect(reloaded?.refreshToken == "rt-new")
}

@Test("a refresh that does not rotate the refresh token is never written back to the Keychain")
func spotifySessionSkipsTheWriteWhenTheRefreshTokenIsUnchanged() async throws {
    // The common path: Spotify echoes no `refresh_token`, so SpotifyTokenExchange carries the
    // previous one forward and only the access token changes.
    let store = try makeStore(spotifyStoredTokens(access: "at-old", refresh: "rt", expiresIn: 30))
    let refreshed = spotifyStoredTokens(access: "at-new", refresh: "rt", expiresIn: 3600)
    let refresher = SpotifyFakeRefresher(.success(refreshed))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    #expect(try await session.accessToken(now: spotifyNow) == "at-new")

    // The stored grant is untouched. An access token lives about an hour, so writing each one back
    // meant an hourly Keychain write — and on an ad-hoc-signed build every write is a password
    // prompt that the read cache cannot absorb. The access token is re-derivable from the refresh
    // token, so the cost is one extra refresh on the next launch.
    let reloaded = try await SpotifyTokenBlob.load(from: store)
    #expect(reloaded?.accessToken == "at-old")
    #expect(reloaded?.refreshToken == "rt")

    // Served from memory: the tick after a refresh neither refreshes nor re-reads.
    #expect(try await session.accessToken(now: spotifyNow) == "at-new")
    #expect(await refresher.calls == 1)
}

@Test("invalidate drops the in-memory grant, so Disconnect actually disconnects")
func spotifySessionInvalidatesItsCache() async throws {
    let store = try makeStore(spotifyStoredTokens(access: "at-live", refresh: "rt", expiresIn: 3600))
    let refresher = SpotifyFakeRefresher(.failure(.providerFailed("must not be called")))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)
    #expect(try await session.accessToken(now: spotifyNow) == "at-live")

    // The disconnect path: the bridge's deleteSecret removes the grant, then the host's
    // onSecretDeleted hook invalidates the session. Without the second half the session would keep
    // serving the credential the user just revoked.
    try await store.delete(reference: SpotifyTokenBlob.reference)
    await session.invalidate()
    await #expect(throws: SpotifyPlaybackError.credentialsMissing) {
        _ = try await session.accessToken(now: spotifyNow)
    }
}

@Test("a refresh with no stored Client ID maps to notConnected (can't renew the grant)")
func spotifySessionRefreshWithoutClientIDThrowsNotConnected() async throws {
    // A refreshable token but no Client ID in the Keychain → the PKCE refresh can't be built.
    let store = try makeStore(
        spotifyStoredTokens(access: "at", refresh: "rt", expiresIn: 10), clientID: nil
    )
    let refresher = SpotifyFakeRefresher(.failure(.providerFailed("must not be called")))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    await #expect(throws: SpotifyPlaybackError.notConnected) {
        _ = try await session.accessToken(now: spotifyNow)
    }
    #expect(await refresher.calls == 0)
}

@Test("no stored authorization maps to credentialsMissing (connect)")
func spotifySessionMissingTokensThrowsCredentialsMissing() async throws {
    let session = SpotifyAuthSession(
        secretStore: try makeStore(nil),
        refresher: SpotifyFakeRefresher(.failure(.providerFailed("unused")))
    )
    await #expect(throws: SpotifyPlaybackError.credentialsMissing) {
        _ = try await session.accessToken(now: spotifyNow)
    }
}

@Test("an expiring token with no refresh token maps to notConnected (reconnect)")
func spotifySessionNoRefreshTokenThrowsNotConnected() async throws {
    let store = try makeStore(spotifyStoredTokens(access: "at", refresh: nil, expiresIn: 10))
    let refresher = SpotifyFakeRefresher(.failure(.providerFailed("must not be called")))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    await #expect(throws: SpotifyPlaybackError.notConnected) {
        _ = try await session.accessToken(now: spotifyNow)
    }
    #expect(await refresher.calls == 0) // no refresh token → never attempts a refresh
}

@Test("a rejected refresh propagates as notConnected")
func spotifySessionRejectedRefreshThrowsNotConnected() async throws {
    let store = try makeStore(spotifyStoredTokens(access: "at", refresh: "rt-revoked", expiresIn: 5))
    let refresher = SpotifyFakeRefresher(.failure(.notConnected))
    let session = SpotifyAuthSession(secretStore: store, refresher: refresher)

    await #expect(throws: SpotifyPlaybackError.notConnected) {
        _ = try await session.accessToken(now: spotifyNow)
    }
}

@Test("the token blob round-trips through the Keychain reference, dates intact")
func spotifyTokenBlobRoundTrips() throws {
    let tokens = spotifyStoredTokens(access: "at", refresh: "rt", expiresIn: 3600, scope: "a b")
    let json = try SpotifyTokenBlob.encode(tokens)
    let decoded = try #require(SpotifyTokenBlob.decode(json))
    #expect(decoded == tokens)
    #expect(SpotifyTokenBlob.reference == "spotify_oauth")
    // A blob that isn't valid JSON decodes to nil (→ credentialsMissing), never a crash.
    #expect(SpotifyTokenBlob.decode("not json") == nil)
}
#endif
