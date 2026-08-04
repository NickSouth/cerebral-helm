// Google token persistence + a session that hands out a valid access token (Gmail integration).
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// The single source of truth for how Google's OAuth tokens are stored: one JSON blob under the
/// Keychain reference `google_oauth`. Both the auth coordinator (which writes after a connect) and
/// the session (which reads and refreshes) go through here, so the format and the reference can
/// never drift apart. Dates are seconds-since-1970 so the blob stays stable and inspectable.
enum GoogleTokenBlob {
    static let reference = "google_oauth"

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

    static func encode(_ tokens: GoogleTokens) throws -> String {
        String(decoding: try encoder().encode(tokens), as: UTF8.self)
    }

    static func decode(_ json: String) -> GoogleTokens? {
        try? decoder().decode(GoogleTokens.self, from: Data(json.utf8))
    }

    static func save(_ tokens: GoogleTokens, to store: any SecretStoreManaging) async throws {
        try await store.store(reference: reference, value: try encode(tokens))
    }

    /// The stored tokens, or `nil` when nothing is stored **or** the blob cannot be decoded — both
    /// mean "no usable Google connection", which the session reports as `notConnected`.
    static func load(from store: any SecretStoreManaging) async throws -> GoogleTokens? {
        let json: String
        do {
            json = try await store.readValue(reference: GoogleTokenBlob.reference)
        } catch {
            return nil // nothing stored
        }
        return decode(json)
    }
}

/// The refresh half of ``GoogleTokenExchange``, abstracted so the session is unit-testable with a
/// fake — the real exchange performs a network call.
public protocol GoogleTokenRefreshing: Sendable {
    func refresh(
        refreshToken: String, clientID: String, clientSecret: String?, now: Date
    ) async throws -> GoogleTokens
}

/// Hands out a valid Google access token, refreshing transparently when the stored one is at or
/// near expiry.
///
/// An **actor**, so a burst of concurrent callers (the publisher's tick landing on top of a report
/// opening) cannot launch overlapping refreshes against the same grant — which Google would answer
/// by invalidating one of them.
///
/// The Client ID is read from the Keychain at refresh time rather than captured at construction:
/// the session is built at launch, before the user has entered one, and the refresh grant needs it.
/// That was learned the hard way on Spotify (NIC-133 increment 7) and is inherited here rather than
/// rediscovered.
///
/// **Failure is honest and specific**, because the remedies differ: `clientIDMissing` means the
/// integration was never set up, and `notConnected` means the grant lapsed — which on an app in
/// Google's "Testing" publishing status happens every 7 days by design, and also whenever the user
/// changes their Google password. Both are ordinary states this surface must report calmly.
public actor GoogleAuthSession {
    /// Refresh this far before the token actually expires, so a request never races the boundary.
    private static let refreshMargin: TimeInterval = 120

    /// The Keychain reference holding the OAuth grant. Public so the host can recognise a
    /// disconnect of *this* secret and invalidate the session, without duplicating the name.
    public static let tokenReference = GoogleTokenBlob.reference

    public static let clientIDReference = "google_client_id"
    /// Google issues Desktop clients a secret and its token endpoint expects it. Optional here
    /// because a client type that genuinely has none (Android/iOS/Chrome) must still work.
    public static let clientSecretReference = "google_client_secret"

    private let secretStore: any SecretStoreManaging
    private let refresher: any GoogleTokenRefreshing
    private var cached: GoogleTokens?

    public init(secretStore: any SecretStoreManaging, refresher: any GoogleTokenRefreshing) {
        self.secretStore = secretStore
        self.refresher = refresher
    }

    /// Forgets the in-memory token, so the next call re-reads the Keychain. Called after a connect
    /// or disconnect: without it a session that cached a dead token would keep using it, and one
    /// that cached a live token would keep working after the user pressed Disconnect.
    public func invalidate() {
        cached = nil
    }

    /// A usable access token, refreshing when needed.
    public func accessToken(now: Date = Date()) async throws -> String {
        if let cached, cached.expiresAt.timeIntervalSince(now) > Self.refreshMargin {
            return cached.accessToken
        }
        guard let stored = try await GoogleTokenBlob.load(from: secretStore) else {
            throw GoogleAuthError.notConnected
        }
        if stored.expiresAt.timeIntervalSince(now) > Self.refreshMargin {
            cached = stored
            return stored.accessToken
        }
        guard let refreshToken = stored.refreshToken else {
            // An access token with nothing to renew it: the connect did not come back with a
            // refresh token, which is what `access_type=offline` + `prompt=consent` exist to
            // prevent. Reconnecting is the only way out.
            throw GoogleAuthError.notConnected
        }
        let clientID = try await clientIDValue()
        let refreshed = try await refresher.refresh(
            refreshToken: refreshToken, clientID: clientID,
            clientSecret: try? await secretStore.readValue(reference: Self.clientSecretReference),
            now: now
        )
        // Google's refresh response identifies no account, so the address is carried forward the
        // same way the refresh token itself is. Without this, every link would silently fall back
        // to the default account an hour after connecting.
        let renewed = refreshed.withAddress(stored.address)
        cached = renewed
        // Persist **only when the refresh token itself rotated** — the same reasoning as
        // ``SpotifyAuthSession/accessToken(now:)``: an hourly write-back of a rotating access token
        // is an hourly Keychain `SecItemUpdate`, and on an ad-hoc-signed build that is an hourly
        // password prompt no read cache can absorb. Google's refresh response never carries a
        // `refresh_token` (see `GoogleTokenExchange.parseTokens`), so in practice this never writes
        // and the stored grant is touched only by connect and disconnect.
        if let rotated = renewed.refreshToken, rotated != stored.refreshToken {
            try await GoogleTokenBlob.save(renewed, to: secretStore)
        }
        return renewed.accessToken
    }

    /// Whether a grant is stored at all — for the settings surface, which needs to show Connect or
    /// Disconnect without triggering a refresh.
    public func isConnected() async -> Bool {
        ((try? await GoogleTokenBlob.load(from: secretStore)) ?? nil) != nil
    }

    private func clientIDValue() async throws -> String {
        guard
            let value = try? await secretStore.readValue(reference: Self.clientIDReference),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GoogleAuthError.clientIDMissing
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
