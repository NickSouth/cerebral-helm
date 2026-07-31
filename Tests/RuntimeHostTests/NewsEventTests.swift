import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-127 Increment 2: mapping a news-provider result into a `DashboardNewsRegion`, and emitting
/// it as a `news.changed` bridge event keyed by relevance profile.

private let newsFixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("headlines map to a ready region, carrying the article url through")
func newsReadyMapping() {
    let region = BridgeEventFactory.news(
        from: .success([
            NewsHeadline(id: "1", title: "Markets steady", source: "Reuters", url: "https://ex.com/a"),
            NewsHeadline(id: "2", title: "Rates held", source: "Bloomberg"),
        ]),
        now: newsFixedNow
    )
    #expect(region.state == .ready)
    #expect(region.headlines.count == 2)
    #expect(region.headlines.first?.title == "Markets steady")
    #expect(region.headlines.first?.source == "Reuters")
    #expect(region.headlines.first?.url == "https://ex.com/a")
    // A headline without a link keeps a nil url — never fabricated.
    #expect(region.headlines.last?.url == nil)
    #expect(region.emptyMessage == nil)
}

@Test("a nil headline url is omitted from the encoded event, not written as null")
func newsOmitsNilURL() throws {
    let region = BridgeEventFactory.news(
        from: .success([NewsHeadline(id: "1", title: "No link", source: "Wire")]),
        now: newsFixedNow
    )
    let event = BridgeEventFactory.newsChangedEvent(
        region: region, profile: "broad", id: "brevt_test00000128", timestamp: newsFixedNow
    )
    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(!json.contains("\"url\":null"))
}

@Test("a ready region is capped at four headlines (owner-raised from the spec's three)")
func newsCapsAtFour() {
    let region = BridgeEventFactory.news(
        from: .success((1...6).map { NewsHeadline(id: "\($0)", title: "H\($0)", source: "S") }),
        now: newsFixedNow
    )
    #expect(region.state == .ready)
    #expect(region.headlines.count == 4)
    #expect(region.headlines.map(\.id) == ["1", "2", "3", "4"])
}

@Test("an empty result maps to an empty region, nothing fabricated")
func newsEmptyMapping() {
    let region = BridgeEventFactory.news(from: .success([]), now: newsFixedNow)
    #expect(region.state == .empty)
    #expect(region.headlines.isEmpty)
    #expect(region.emptyMessage == "No headlines right now.")
}

@Test("a missing credential maps to an honest unavailable region that guides to Settings")
func newsCredentialsMissingMapping() {
    let region = BridgeEventFactory.news(
        from: .failure(NewsError.credentialsMissing), now: newsFixedNow
    )
    #expect(region.state == .unavailable)
    #expect(region.headlines.isEmpty)
    #expect(region.emptyMessage == "Add your NewsData API key in Settings → Setup to see news.")
}

@Test("a generic provider failure maps to a generic unavailable, never leaking the diagnostic")
func newsProviderFailureMapping() {
    let region = BridgeEventFactory.news(
        from: .failure(NewsError.providerFailed("secret-token=abc123 network down")), now: newsFixedNow
    )
    #expect(region.state == .unavailable)
    #expect(region.emptyMessage == "News isn't available right now.")
    // The raw diagnostic (which could carry a token) is never surfaced.
    #expect(region.emptyMessage?.contains("abc123") == false)
}

@Test("the region emits as a news.changed event carrying its profile; round-trips the contract")
func newsEmitsChangedEvent() throws {
    let region = BridgeEventFactory.news(
        from: .success([NewsHeadline(id: "1", title: "Markets steady", source: "Reuters")]),
        now: newsFixedNow
    )
    let event = BridgeEventFactory.newsChangedEvent(
        region: region, profile: "broad", id: "brevt_test00000127", timestamp: newsFixedNow
    )

    #expect(event.type == .newsChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"news.changed\""))
    #expect(json.contains("\"profile\":\"broad\""))
    #expect(json.contains("\"title\":\"Markets steady\""))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .newsChanged)
    #expect(decoded.eventID == "brevt_test00000127")
}
