// Streaming the Spotify now-playing widget (NIC-133) — the Entertainment left-slot producer.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// Resolves a valid Spotify access token from the ``SpotifyAuthSession`` (refreshing as needed),
/// reads the currently-playing track, and emits one `widget.data.changed` event for the `spotify`
/// widget per tick (NIC-133). The dashboard folds it into `liveWidgets`, which the Entertainment
/// left rail renders (NIC-131 blueprint) — surviving mode switches by construction.
///
/// Mirrors ``ReleasesPublisher``'s visibility discipline but on an **adaptive fast cadence**,
/// because the widget should track the current track without feeling stale: it polls every
/// `playingIntervalMs` (default 3s) while something is playing — so a track change or a skip on any
/// device shows within a few seconds — and backs off to `idleIntervalMs` (default 12s) when paused
/// or nothing is playing, to spare the API. The loop is deactivated while the dashboard isn't
/// visible (the shell flips `setActive` from occlusion state) and reactivation emits immediately.
/// Honest states come straight from the session/provider: not connected → "connect"; a rejected/dead
/// authorization → "reconnect"; nothing playing → a healthy empty; a provider failure → a generic
/// unavailable. `refresh()` is called right after a successful connect, and after a playback control
/// (via the refresh signal), so the track appears at once rather than on the next tick.
public actor SpotifyPublisher {
    private let session: SpotifyAuthSession
    private let provider: any SpotifyPlaybackProvider
    private let playingIntervalNanos: UInt64
    private let idleIntervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        session: SpotifyAuthSession,
        provider: any SpotifyPlaybackProvider,
        playingIntervalMs: Int = 3_000,
        idleIntervalMs: Int = 12_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.session = session
        self.provider = provider
        self.playingIntervalNanos = UInt64(playingIntervalMs) * 1_000_000
        self.idleIntervalNanos = UInt64(idleIntervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the widget
    /// populates as soon as the stream starts rather than after one interval. The next interval is
    /// short while a track is playing and longer otherwise.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let playing = await self.tickIfActive()
                try? await Task.sleep(nanoseconds: playing ? self.playingIntervalNanos : self.idleIntervalNanos)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Emit a fresh sample now, regardless of cadence — used right after a successful connect so the
    /// now-playing track appears immediately instead of waiting out the interval.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately
    /// instead of waiting out the current interval.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick()
        }
    }

    /// Ticks when active; returns whether a track is currently playing (drives the adaptive cadence).
    @discardableResult
    private func tickIfActive() async -> Bool {
        guard active else { return false }
        return await tick()
    }

    /// Samples now-playing, emits the widget event, and returns whether a track is actively playing.
    @discardableResult
    private func tick() async -> Bool {
        let result: Swift.Result<SpotifyNowPlaying?, Error>
        var recent: [SpotifyRecentTrack] = []
        do {
            let token = try await session.accessToken()
            let nowPlaying = try await provider.nowPlaying(accessToken: token)
            // Nothing playing → fetch the recently-played "jump back in" list (best-effort; a token
            // without the recently-played scope just yields none, and the widget stays a plain empty).
            if nowPlaying == nil {
                recent = (try? await provider.recentlyPlayed(accessToken: token)) ?? []
            }
            result = .success(nowPlaying)
        } catch {
            // credentialsMissing → "connect"; notConnected → "reconnect"; anything else → generic
            // unavailable. The mapping words each honestly and never leaks a diagnostic.
            result = .failure(error)
        }

        let widget = BridgeEventFactory.spotifyWidget(from: result, recent: recent, now: Date())
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: "spotify",
            widget: widget,
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        if let data = try? BridgeMessageCoding.encoder().encode(event),
           let json = String(data: data, encoding: .utf8) {
            emit(json)
        }
        if case let .success(nowPlaying?) = result { return nowPlaying.isPlaying }
        return false
    }
}
#endif
