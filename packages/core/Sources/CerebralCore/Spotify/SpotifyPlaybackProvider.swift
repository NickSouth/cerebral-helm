import Foundation

/// The track currently playing on Spotify for the Entertainment "Spotify" widget (NIC-133).
/// Produced by a ``SpotifyPlaybackProvider`` and mapped to the widget envelope by the live
/// producer (Increment 7). `album` and `artworkImage` are optional because Spotify may not
/// provide them for every item — they are omitted, never fabricated. `artworkImage` is a
/// self-contained `data:` URI (base64) because the dashboard's `cerebral://` origin does not
/// load external image URLs; the adapter fetches it natively (Increment 5). `isPlaying`
/// distinguishes actively playing from paused — a paused track is still the current one.
public struct SpotifyNowPlaying: Equatable, Sendable {
    /// Track title.
    public let track: String
    /// Primary artist (a concrete provider joins multiple artists, Increment 5).
    public let artist: String
    /// Album name, or nil when Spotify has none for the item.
    public let album: String?
    /// Album artwork as a `data:` URI, or nil when there was no artwork or it couldn't be fetched
    /// — the card then shows a music-note placeholder, never a broken image.
    public let artworkImage: String?
    /// Whether the track is actively playing (vs paused).
    public let isPlaying: Bool
    /// The active Spotify device's name (e.g. "Nick's MacBook Pro"), or nil when unknown.
    public let deviceName: String?
    /// Playback position within the track, in milliseconds, or nil when unknown.
    public let progressMs: Int?
    /// Track length in milliseconds, or nil when unknown.
    public let durationMs: Int?

    public init(
        track: String, artist: String, album: String? = nil, artworkImage: String? = nil,
        isPlaying: Bool, deviceName: String? = nil, progressMs: Int? = nil, durationMs: Int? = nil
    ) {
        self.track = track
        self.artist = artist
        self.album = album
        self.artworkImage = artworkImage
        self.isPlaying = isPlaying
        self.deviceName = deviceName
        self.progressMs = progressMs
        self.durationMs = durationMs
    }
}

/// Why a now-playing fetch could not be produced. Kept coarse and provider-neutral so the event
/// mapping degrades honestly, distinguishing three states the widget words differently:
/// ``credentialsMissing`` (no Spotify authorization is stored — thrown by the publisher when the
/// Keychain reference is unbound, Increment 7 — "connect"), ``notConnected`` (a stored
/// authorization Spotify rejected, e.g. a revoked/expired token that could not be refreshed —
/// "reconnect"), and ``providerFailed`` (a network/API/parse failure — a generic unavailable that
/// never leaks the diagnostic). Nothing playing is *not* an error — it is a successful `nil`
/// result. FR-CFG-03/FR-SAF-07: a missing or dead credential becomes honest guidance, never a
/// fabricated track.
public enum SpotifyPlaybackError: Error, Equatable, Sendable {
    /// No Spotify authorization is configured — the widget should guide the user to connect.
    case credentialsMissing
    /// A stored authorization was rejected by Spotify — the widget should guide the user to reconnect.
    case notConnected
    /// The provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that reads the track currently playing on Spotify (NIC-133). Provider-neutral and
/// credential-driven: the caller (the ``SpotifyPublisher``, Increment 7) resolves a valid access
/// token from the auth session and passes it in, so this contract never touches the secret store.
/// Async because a real provider performs a network fetch (the Spotify Web API, Increment 5); the
/// mock resolves synchronously. Returns `nil` when nothing is playing (Spotify's 204 / no active
/// device — a healthy `empty` state, not a failure); throws ``SpotifyPlaybackError`` otherwise.
public protocol SpotifyPlaybackProvider: Sendable {
    func nowPlaying(accessToken: String) async throws -> SpotifyNowPlaying?
}

/// A fixed-outcome ``SpotifyPlaybackProvider`` for pre-Mac builds and tests: it ignores the token
/// and always yields the track (or nil, or throws the error) it was constructed with.
public struct MockSpotifyPlaybackProvider: SpotifyPlaybackProvider {
    private let outcome: Result<SpotifyNowPlaying?, SpotifyPlaybackError>

    /// Succeeds with the given track, or with `nil` to model nothing playing.
    public init(nowPlaying: SpotifyNowPlaying?) {
        self.outcome = .success(nowPlaying)
    }

    public init(error: SpotifyPlaybackError) {
        self.outcome = .failure(error)
    }

    public func nowPlaying(accessToken: String) async throws -> SpotifyNowPlaying? {
        try outcome.get()
    }
}
