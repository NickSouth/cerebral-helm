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
    /// The Keychain reference holding the OAuth grant. Public so the host can recognise a
    /// disconnect of *this* secret and invalidate the session, without duplicating the name.
    public static let tokenReference = SpotifyTokenBlob.reference

    private let secretStore: any SecretStoreManaging
    private let refresher: any SpotifyTokenRefreshing
    private let clientIDReference: String
    /// Refresh when the access token expires within this window, so a tick never uses a token that
    /// lapses mid-request.
    private let refreshMargin: TimeInterval
    /// The live grant, held in memory so a rotating access token never has to be written back to
    /// the Keychain. See ``accessToken(now:)``.
    private var cached: SpotifyTokens?

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

    /// Forgets the in-memory grant, so the next call re-reads the Keychain. Called after a connect
    /// or disconnect: without it a session holding a revoked token would keep playing, and one
    /// holding a dead token would keep failing after the user reconnected. (Mirrors
    /// ``GoogleAuthSession/invalidate()`` — the same hazard, the same remedy.)
    public func invalidate() {
        cached = nil
    }

    public func accessToken(now: Date = Date()) async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSince(now) > refreshMargin {
            return cached.accessToken
        }
        guard let tokens = try await SpotifyTokenBlob.load(from: secretStore) else {
            throw SpotifyPlaybackError.credentialsMissing
        }
        if tokens.expiresAt.timeIntervalSince(now) > refreshMargin {
            cached = tokens
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
        cached = refreshed
        // Persist **only when the refresh token itself rotated**. An access token lives about an
        // hour, so writing every refresh back meant a Keychain `SecItemUpdate` roughly hourly — and
        // while the app is ad-hoc signed each of those is a password prompt the read cache cannot
        // absorb (a write has to reach the Keychain). The access token is ephemeral and fully
        // re-derivable from the refresh token, so skipping the write costs at most one extra
        // refresh on the next launch. Spotify usually echoes no `refresh_token` and
        // ``SpotifyTokenExchange`` carries the previous one forward, so this is the common path.
        //
        // The `!= nil` guard is deliberate: a refresher that returned a nil refresh token would
        // otherwise persist a blob that can never be renewed again, silently breaking the grant.
        if let rotated = refreshed.refreshToken, rotated != tokens.refreshToken {
            try await SpotifyTokenBlob.save(refreshed, to: secretStore)
        }
        return refreshed.accessToken
    }

    /// The scope string of the stored grant, or nil when nothing is stored or the grant didn't
    /// echo one. A refresh never widens a grant, so a token stored before a scope was added to
    /// ``SpotifyTokenExchange/playbackScopes`` lacks it until the user reconnects — the publisher
    /// uses this to word the idle state honestly ("reconnect to see recent tracks") instead of
    /// letting the recently-played call fail silently into a plain empty.
    public func grantedScope() async -> String? {
        guard let tokens = try? await SpotifyTokenBlob.load(from: secretStore) else { return nil }
        return tokens.scope
    }
}
#endif
