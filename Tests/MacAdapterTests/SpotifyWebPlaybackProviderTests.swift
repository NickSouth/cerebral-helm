// NIC-133 Increment 5: Spotify now-playing request building, response parsing, artwork selection,
// and image embedding. The pure static helpers are unit-tested; the live call is smoked once a
// real Spotify authorization exists (after Increment 6).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the request targets the currently-playing endpoint with the token in the header, not the URL")
func spotifyPlayerRequestCarriesBearerToken() throws {
    let request = try #require(SpotifyWebPlaybackProvider.makeRequest(
        host: "https://api.spotify.com", accessToken: "secret-access-token"
    ))
    let url = try #require(request.url)
    #expect(url.absoluteString == "https://api.spotify.com/v1/me/player")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-access-token")
    // The token rides the header — never the URL, so it can't leak into logs.
    #expect(!url.absoluteString.contains("secret-access-token"))
}

@Test("a playing track parses its title, artists, album, artwork, device, and progress")
func spotifyParsesPlayingTrack() throws {
    let json = Data("""
    { "is_playing": true, "progress_ms": 83000,
      "device": { "name": "Nick's MacBook Pro" },
      "item": {
        "name": "Weightless",
        "duration_ms": 480000,
        "artists": [{ "name": "Marconi Union" }, { "name": "Ambient Collective" }],
        "album": {
          "name": "Ambient Transmissions Vol. 2",
          "images": [
            { "url": "https://img/640.jpg", "width": 640 },
            { "url": "https://img/300.jpg", "width": 300 },
            { "url": "https://img/64.jpg", "width": 64 }
          ]
        }
      } }
    """.utf8)

    let parsed = try #require(try SpotifyWebPlaybackProvider.parse(json))
    #expect(parsed.track == "Weightless")
    #expect(parsed.artist == "Marconi Union, Ambient Collective")
    #expect(parsed.album == "Ambient Transmissions Vol. 2")
    #expect(parsed.isPlaying == true)
    // The smallest image at least 160px wide (the 300px one) is chosen — small data URI, retina-ok.
    #expect(parsed.artworkURL?.absoluteString == "https://img/300.jpg")
    // The active device and the progress/duration for the widget's progress bar.
    #expect(parsed.deviceName == "Nick's MacBook Pro")
    #expect(parsed.progressMs == 83000)
    #expect(parsed.durationMs == 480000)
}

@Test("a paused track is still the current track (isPlaying false), never dropped")
func spotifyParsesPausedTrack() throws {
    let json = Data("""
    { "is_playing": false, "item": { "name": "Paused Song", "artists": [{ "name": "Someone" }] } }
    """.utf8)
    let parsed = try #require(try SpotifyWebPlaybackProvider.parse(json))
    #expect(parsed.track == "Paused Song")
    #expect(parsed.isPlaying == false)
    #expect(parsed.album == nil) // no album provided → omitted, never fabricated
    #expect(parsed.artworkURL == nil)
}

@Test("no item (an ad or private session) parses to nil — nothing to show")
func spotifyParsesNoItemAsNil() throws {
    #expect(try SpotifyWebPlaybackProvider.parse(Data("{ \"is_playing\": true, \"item\": null }".utf8)) == nil)
    // A blank title is likewise nothing showable.
    let blank = Data("{ \"item\": { \"name\": \"   \" } }".utf8)
    #expect(try SpotifyWebPlaybackProvider.parse(blank) == nil)
}

@Test("a podcast episode uses the show name as the artist and its own artwork")
func spotifyParsesPodcastEpisode() throws {
    let json = Data("""
    { "is_playing": true, "currently_playing_type": "episode",
      "item": {
        "name": "Episode 42",
        "show": { "name": "The Ambient Hour" },
        "images": [{ "url": "https://img/ep300.jpg", "width": 300 }]
      } }
    """.utf8)
    let parsed = try #require(try SpotifyWebPlaybackProvider.parse(json))
    #expect(parsed.track == "Episode 42")
    #expect(parsed.artist == "The Ambient Hour") // no artists → show name
    #expect(parsed.album == nil)
    #expect(parsed.artworkURL?.absoluteString == "https://img/ep300.jpg")
}

@Test("image selection prefers the smallest ≥160px, else the largest, else the last when unsized")
func spotifyPicksArtwork() {
    func img(_ url: String, _ width: Int?) -> SpotifyWebPlaybackProvider.Response.Image {
        SpotifyWebPlaybackProvider.Response.Image(url: url, width: width)
    }
    // Smallest at least 160 wins.
    #expect(SpotifyWebPlaybackProvider.pickImageURL(from: [
        img("a", 640), img("b", 300), img("c", 64)
    ])?.absoluteString == "b")
    // None reach 160 → the largest available.
    #expect(SpotifyWebPlaybackProvider.pickImageURL(from: [
        img("small", 64), img("tiny", 32)
    ])?.absoluteString == "small")
    // No widths → Spotify lists largest-first, so the last (smallest) keeps the data URI small.
    #expect(SpotifyWebPlaybackProvider.pickImageURL(from: [
        img("big", nil), img("little", nil)
    ])?.absoluteString == "little")
    #expect(SpotifyWebPlaybackProvider.pickImageURL(from: []) == nil)
}

@Test("artwork bytes become a data URI only when they decode as a real image")
func spotifyArtworkDataURI() throws {
    let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    let png = try #require(Data(base64Encoded: pngBase64))
    let uri = try #require(SpotifyWebPlaybackProvider.artworkDataURI(png))
    #expect(uri.hasPrefix("data:image/png;base64,"))
    // Garbage (an HTML error page) is not vouched for — an honest nil, never a broken image.
    #expect(SpotifyWebPlaybackProvider.artworkDataURI(Data("<html>nope</html>".utf8)) == nil)
    #expect(SpotifyWebPlaybackProvider.artworkDataURI(Data()) == nil)
    #expect(SpotifyWebPlaybackProvider.artworkDataURI(png, byteCap: 10) == nil)
}

@Test("malformed JSON throws providerFailed, never a fabricated track")
func spotifyParseFailure() {
    #expect(throws: SpotifyPlaybackError.self) {
        _ = try SpotifyWebPlaybackProvider.parse(Data("not json".utf8))
    }
}
#endif
