import Foundation
import Testing

import CerebralCore

/// NIC-133 Increment 2: the portable now-playing contract — a provider-neutral ``SpotifyNowPlaying``
/// + ``SpotifyPlaybackProvider`` port with a fixed-outcome mock. The real Spotify Web API fetch
/// lands in the Mac adapter (Increment 5). Test funcs are prefixed `spotify` because Swift test
/// targets share a module-global namespace.

@Test("the mock provider yields its constructed track, ignoring the token")
func spotifyMockYieldsTrack() async throws {
    let provider = MockSpotifyPlaybackProvider(
        nowPlaying: SpotifyNowPlaying(track: "Weightless", artist: "Marconi Union", isPlaying: true)
    )

    let track = try await provider.nowPlaying(accessToken: "ignored")
    #expect(track?.track == "Weightless")
    #expect(track?.artist == "Marconi Union")
    #expect(track?.isPlaying == true)
    // Optional album/artwork are preserved as nil, never fabricated.
    #expect(track?.album == nil)
    #expect(track?.artworkImage == nil)
}

@Test("the mock provider yields nil to model nothing playing")
func spotifyMockYieldsNothingPlaying() async throws {
    let provider = MockSpotifyPlaybackProvider(nowPlaying: nil)
    let track = try await provider.nowPlaying(accessToken: "ignored")
    #expect(track == nil)
}

@Test("the mock provider throws its constructed error")
func spotifyMockThrowsError() async {
    let provider = MockSpotifyPlaybackProvider(error: .credentialsMissing)
    await #expect(throws: SpotifyPlaybackError.credentialsMissing) {
        try await provider.nowPlaying(accessToken: "")
    }
}

@Test("SpotifyPlaybackError distinguishes connect, reconnect, and provider-failure states")
func spotifyErrorCasesAreDistinct() {
    #expect(SpotifyPlaybackError.credentialsMissing != SpotifyPlaybackError.notConnected)
    #expect(SpotifyPlaybackError.credentialsMissing != SpotifyPlaybackError.providerFailed("boom"))
    #expect(SpotifyPlaybackError.notConnected != SpotifyPlaybackError.providerFailed("boom"))
    #expect(SpotifyPlaybackError.providerFailed("a") == SpotifyPlaybackError.providerFailed("a"))
}
