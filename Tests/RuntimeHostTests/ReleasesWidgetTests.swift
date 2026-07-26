import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-134 Increment 2: mapping a releases-provider result into the `releases` widget envelope,
/// and emitting it as a `widget.data.changed` bridge event (the NIC-131 live-widget pipe).
/// Test funcs are prefixed `releases` because Swift test targets share a module-global namespace
/// (e.g. `readyMapping` is already claimed by RepositoriesWidgetTests).

private func release(_ id: String, _ title: String, _ mediaType: ReleaseMediaType, year: Int?) -> ReleaseItem {
    ReleaseItem(id: id, title: title, mediaType: mediaType, year: year)
}

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a non-empty fetch maps to a ready widget with one row per release")
func releasesReadyMapping() {
    let widget = BridgeEventFactory.releasesWidget(
        from: .success([
            release("1", "Dune: Part Two", .movie, year: 2024),
            release("2", "The Bear", .tv, year: nil),
        ]),
        now: fixedNow
    )

    #expect(widget.widgetId == "releases")
    #expect(widget.state == "ready")
    #expect(widget.headline == "New & hot")
    #expect(widget.emptyMessage == nil)
    #expect(widget.freshness?.observedAt == fixedNow)
    #expect(widget.data?.items.count == 2)
    #expect(widget.data?.items.first?.mediaType == "movie")
    #expect(widget.data?.items.first?.year == 2024)
    // An unknown year is left nil, never fabricated.
    #expect(widget.data?.items.last?.year == nil)
    #expect(widget.data?.items.last?.mediaType == "tv")
}

@Test("a readable-but-empty result maps to an empty widget with an honest message")
func releasesEmptyMapping() {
    let widget = BridgeEventFactory.releasesWidget(from: .success([]), now: fixedNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a missing credential maps to unavailable with guidance to add the API key")
func releasesCredentialsMissingMapping() {
    let widget = BridgeEventFactory.releasesWidget(
        from: .failure(ReleaseError.credentialsMissing), now: fixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.contains("TMDB API key") == true)
}

@Test("a provider failure maps to a generic unavailable, never a fabricated list")
func releasesProviderFailureMapping() {
    let widget = BridgeEventFactory.releasesWidget(
        from: .failure(ReleaseError.providerFailed("HTTP 500")), now: fixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    // The generic failure does not leak the raw diagnostic and is not the credentials message.
    #expect(widget.emptyMessage?.contains("TMDB API key") == false)
    #expect(widget.emptyMessage?.contains("HTTP 500") == false)
}

@Test("the widget emits as a widget.data.changed event; a nil year is omitted, not null")
func releasesEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.releasesWidget(
        from: .success([
            release("1", "Dune: Part Two", .movie, year: 2024),
            release("2", "Nosferatu", .movie, year: nil),
        ]),
        now: fixedNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "releases", widget: widget, id: "brevt_test00000134", timestamp: fixedNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"releases\""))
    #expect(json.contains("\"mediaType\":\"movie\""))
    #expect(json.contains("\"year\":2024"))
    // The synthesized encoding omits a nil year rather than writing an explicit null.
    #expect(!json.contains("\"year\":null"))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000134")
}
