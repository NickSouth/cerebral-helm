// Spotify token persistence + a session that hands out a valid access token (NIC-133).
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// The single source of truth for how Spotify's OAuth tokens are stored: one JSON blob under the
/// Keychain reference `spotify_oauth` (NIC-133). Both the auth coordinator (which writes after a
/// connect/refresh) and the session (which reads) go through here so the format and reference can
/// never drift. Dates are encoded as seconds-since-1970 so the blob is stable and inspectable.
enum SpotifyTokenBlob {
    static let reference = "spotify_oauth"

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func encode(_ tokens: SpotifyTokens) throws -> String {
        String(decoding: try encoder().encode(tokens), as: UTF8.self)
    }

    static func decode(_ json: String) -> SpotifyTokens? {
        try? decoder().decode(SpotifyTokens.self, from: Data(json.utf8))
    }

    static func save(_ tokens: SpotifyTokens, to store: any SecretStoreManaging) async throws {
        try await store.store(reference: reference, value: try encode(tokens))
    }

    /// Loads the stored tokens, or `nil` when nothing is stored **or** the blob can't be decoded —
    /// both mean "no usable Spotify connection", which the session maps to
    /// ``SpotifyPlaybackError/credentialsMissing`` ("connect").
    static func load(from store: any SecretStoreManaging) async throws -> SpotifyTokens? {
        let json: String
        do {
            json = try await store.readValue(reference: reference)
        } catch {
            return nil // no stored authorization
        }
        return decode(json)
    }
}

/// The refresh half of ``SpotifyTokenExchange``, abstracted so the session can be unit-tested with a
/// fake (the real exchange performs a network call). ``SpotifyTokenExchange`` conforms in its own
/// file (a `Sendable`-inheriting conformance must live beside the type).
public protocol SpotifyTokenRefreshing: Sendable {
    func refresh(refreshToken: String, clientID: String, now: Date) async throws -> SpotifyTokens
}

/// Hands out a valid Spotify access token, refreshing transparently when the stored one is at or
/// near expiry (NIC-133). The publisher (Increment 7) calls ``accessToken(now:)`` each tick and
/// passes the result to the ``SpotifyPlaybackProvider``; the session never exposes the refresh
/// token. It throws honestly: ``SpotifyPlaybackError/credentialsMissing`` when nothing is stored
/// (connect), and ``SpotifyPlaybackError/notConnected`` when the stored authorization can't be
/// refreshed — a missing refresh token, a missing Client ID, or Spotify rejecting it (reconnect).
/// An actor so a burst of concurrent ticks can't launch overlapping refreshes.
///
/// The Client ID is read from the Keychain (`spotify_client_id`) at refresh time rather than fixed
/// at construction, because the publisher is built at launch — before the user has entered it — and
/// the PKCE refresh grant needs it.
public actor SpotifyAuthSession {
    private let secretStore: any SecretStoreManaging
    private let refresher: any SpotifyTokenRefreshing
    private let clientIDReference: String
    /// Refresh when the access token expires within this window, so a tick never uses a token that
    /// lapses mid-request.
    private let refreshMargin: TimeInterval

    public init(
        secretStore: any SecretStoreManaging,
        refresher: any SpotifyTokenRefreshing,
        clientIDReference: String = "spotify_client_id",
        refreshMargin: TimeInterval = 60
    ) {
        self.secretStore = secretStore
        self.refresher = refresher
        self.clientIDReference = clientIDReference
        self.refreshMargin = refreshMargin
    }

    public func accessToken(now: Date = Date()) async throws -> String {
        guard let tokens = try await SpotifyTokenBlob.load(from: secretStore) else {
            throw SpotifyPlaybackError.credentialsMissing
        }
        if tokens.expiresAt.timeIntervalSince(now) > refreshMargin {
            return tokens.accessToken // still valid, no refresh needed
        }
        guard let refreshToken = tokens.refreshToken else {
            // Nothing to refresh with — the stored authorization is unusable.
            throw SpotifyPlaybackError.notConnected
        }
        // The PKCE refresh grant needs the (public) Client ID; without it the token can't be
        // renewed, so the connection is effectively dead → reconnect.
        let clientID = (try? await secretStore.readValue(reference: clientIDReference))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clientID, !clientID.isEmpty else {
            throw SpotifyPlaybackError.notConnected
        }
        let refreshed = try await refresher.refresh(refreshToken: refreshToken, clientID: clientID, now: now)
        try await SpotifyTokenBlob.save(refreshed, to: secretStore)
        return refreshed.accessToken
    }
}
#endif
