// NIC-133 Increment 7: streaming the spotify now-playing widget as widget.data.changed events,
// keyed off a Keychain-backed OAuth session that hands out a valid access token.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools
@testable import CerebralMacAdapters

private final class SpotifyEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

private func waitForSpotify(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

/// A refresher that must never run in these tests (the seeded token is valid far into the future).
private struct SpotifyUnusedRefresher: SpotifyTokenRefreshing {
    func refresh(refreshToken: String, clientID: String, now: Date) async throws -> SpotifyTokens {
        throw SpotifyPlaybackError.providerFailed("refresh must not be called")
    }
}

/// A store holding a valid (far-future) token blob + a Client ID, so the session returns the access
/// token without refreshing.
private func spotifyConnectedStore() throws -> MockSecretStore {
    let tokens = SpotifyTokens(
        accessToken: "at-secret", refreshToken: "rt",
        expiresAt: Date().addingTimeInterval(3600), scope: nil
    )
    return MockSecretStore(values: [
        SpotifyTokenBlob.reference: try SpotifyTokenBlob.encode(tokens),
        "spotify_client_id": "client-abc",
    ])
}

@Test("with a valid token the publisher emits a ready now-playing widget; the token never leaks")
func spotifyPublisherEmitsReady() async throws {
    let collector = SpotifyEventCollector()
    let session = SpotifyAuthSession(secretStore: try spotifyConnectedStore(), refresher: SpotifyUnusedRefresher())
    let publisher = SpotifyPublisher(
        session: session,
        provider: MockSpotifyPlaybackProvider(
            nowPlaying: SpotifyNowPlaying(track: "Weightless", artist: "Marconi Union", isPlaying: true)
        ),
        playingIntervalMs: 50, idleIntervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSpotify(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .widgetDataChanged)
    #expect(collector.all[0].contains("\"widgetId\":\"spotify\""))
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"track\":\"Weightless\""))
    #expect(collector.all[0].contains("\"isPlaying\":true"))
    // The access token is never part of the emitted event.
    #expect(!collector.all[0].contains("at-secret"))
}

@Test("with no stored authorization the publisher emits an honest connect state")
func spotifyPublisherEmitsConnect() async throws {
    let collector = SpotifyEventCollector()
    let session = SpotifyAuthSession(secretStore: MockSecretStore(), refresher: SpotifyUnusedRefresher())
    let publisher = SpotifyPublisher(
        session: session,
        provider: MockSpotifyPlaybackProvider(nowPlaying: nil),
        playingIntervalMs: 50, idleIntervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSpotify(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("Connect Spotify"))
}

@Test("a connected account with nothing playing emits a healthy empty state")
func spotifyPublisherEmitsNothingPlaying() async throws {
    let collector = SpotifyEventCollector()
    let session = SpotifyAuthSession(secretStore: try spotifyConnectedStore(), refresher: SpotifyUnusedRefresher())
    let publisher = SpotifyPublisher(
        session: session,
        provider: MockSpotifyPlaybackProvider(nowPlaying: nil),
        playingIntervalMs: 50, idleIntervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSpotify(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"empty\""))
    #expect(collector.all[0].contains("Nothing playing"))
}

@Test("a paused spotify publisher emits nothing; resuming emits immediately")
func spotifyPublisherPauseResume() async throws {
    let collector = SpotifyEventCollector()
    let session = SpotifyAuthSession(secretStore: try spotifyConnectedStore(), refresher: SpotifyUnusedRefresher())
    let publisher = SpotifyPublisher(
        session: session,
        provider: MockSpotifyPlaybackProvider(
            nowPlaying: SpotifyNowPlaying(track: "Weightless", artist: "Marconi Union", isPlaying: true)
        ),
        playingIntervalMs: 40, idleIntervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForSpotify(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitForSpotify(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
