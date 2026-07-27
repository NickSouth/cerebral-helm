import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-133 Increment 2: mapping a now-playing result into the `spotify` widget envelope, and
/// emitting it as a `widget.data.changed` bridge event (the NIC-131 live-widget pipe). Test funcs
/// are prefixed `spotify` because Swift test targets share a module-global namespace.

private let spotifyFixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a current track maps to a ready widget with the flat now-playing payload")
func spotifyReadyMapping() {
    let widget = BridgeEventFactory.spotifyWidget(
        from: .success(
            SpotifyNowPlaying(
                track: "Weightless", artist: "Marconi Union",
                album: "Ambient Transmissions Vol. 2", artworkImage: "data:image/png;base64,AAAA",
                isPlaying: true
            )
        ),
        now: spotifyFixedNow
    )

    #expect(widget.widgetId == "spotify")
    #expect(widget.state == "ready")
    #expect(widget.headline == "Now playing")
    #expect(widget.emptyMessage == nil)
    #expect(widget.freshness?.observedAt == spotifyFixedNow)
    #expect(widget.data?.track == "Weightless")
    #expect(widget.data?.artist == "Marconi Union")
    #expect(widget.data?.album == "Ambient Transmissions Vol. 2")
    #expect(widget.data?.artworkImage == "data:image/png;base64,AAAA")
    #expect(widget.data?.isPlaying == true)
}

@Test("nothing playing (a successful nil) maps to a healthy empty widget")
func spotifyNothingPlayingMapping() {
    let widget = BridgeEventFactory.spotifyWidget(from: .success(nil), now: spotifyFixedNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a missing credential maps to unavailable with guidance to connect")
func spotifyCredentialsMissingMapping() {
    let widget = BridgeEventFactory.spotifyWidget(
        from: .failure(SpotifyPlaybackError.credentialsMissing), now: spotifyFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.contains("Connect Spotify") == true)
}

@Test("a rejected authorization maps to unavailable with guidance to reconnect")
func spotifyNotConnectedMapping() {
    let widget = BridgeEventFactory.spotifyWidget(
        from: .failure(SpotifyPlaybackError.notConnected), now: spotifyFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.contains("Reconnect Spotify") == true)
}

@Test("a provider failure maps to a generic unavailable, never leaking the diagnostic")
func spotifyProviderFailureMapping() {
    let widget = BridgeEventFactory.spotifyWidget(
        from: .failure(SpotifyPlaybackError.providerFailed("HTTP 500")), now: spotifyFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    // The generic failure is neither the connect nor reconnect message, and never leaks the raw text.
    #expect(widget.emptyMessage?.contains("Connect Spotify") == false)
    #expect(widget.emptyMessage?.contains("Reconnect Spotify") == false)
    #expect(widget.emptyMessage?.contains("HTTP 500") == false)
}

@Test("the widget emits as a widget.data.changed event; a nil album is omitted, not null")
func spotifyEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.spotifyWidget(
        from: .success(
            SpotifyNowPlaying(track: "Weightless", artist: "Marconi Union", isPlaying: false)
        ),
        now: spotifyFixedNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "spotify", widget: widget, id: "brevt_test00000133", timestamp: spotifyFixedNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"spotify\""))
    #expect(json.contains("\"track\":\"Weightless\""))
    #expect(json.contains("\"isPlaying\":false"))
    // The synthesized encoding omits a nil album rather than writing an explicit null.
    #expect(!json.contains("\"album\":null"))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000133")
}
