import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-128 Increment 2: mapping a batch of stock-quote results into the `stocks` widget envelope
/// and emitting it as a `widget.data.changed` bridge event (the NIC-131 live-widget pipe). Test
/// funcs are prefixed `stocks` because Swift test targets share a module-global namespace.

private func stockRow(
    _ symbol: String, _ price: Double?, _ change: Double?, _ changePercent: Double?,
    history: [Double]? = nil
) -> StockQuoteResult {
    StockQuoteResult(
        symbol: symbol,
        quote: price.map { StockQuote(price: $0, change: change ?? 0, changePercent: changePercent ?? 0) },
        history: history
    )
}

private let stocksFixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a non-empty batch maps to a ready widget with one row per ticker")
func stocksReadyMapping() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([
            stockRow("SPY", 543.21, 3.24, 0.6),
            stockRow("AAPL", 227.15, -0.68, -0.3),
        ]),
        now: stocksFixedNow
    )

    #expect(widget.widgetId == "stocks")
    #expect(widget.state == "ready")
    #expect(widget.headline == "2 tickers")
    #expect(widget.emptyMessage == nil)
    #expect(widget.freshness?.observedAt == stocksFixedNow)
    #expect(widget.data?.items.count == 2)
    #expect(widget.data?.items.first?.symbol == "SPY")
    #expect(widget.data?.items.first?.price == 543.21)
    #expect(widget.data?.items.last?.change == -0.68)
}

@Test("a single ticker uses the singular headline")
func stocksSingularHeadline() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([stockRow("SPY", 1, 0, 0)]), now: stocksFixedNow
    )
    #expect(widget.headline == "1 ticker")
}

@Test("an unresolved symbol keeps its ticker but omits figures, never fabricating a price")
func stocksUnresolvedRowOmitsFigures() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([stockRow("SPY", 543.21, 3.24, 0.6), stockRow("???", nil, nil, nil)]),
        now: stocksFixedNow
    )
    #expect(widget.state == "ready")
    #expect(widget.data?.items.last?.symbol == "???")
    #expect(widget.data?.items.last?.price == nil)
    #expect(widget.data?.items.last?.change == nil)
}

@Test("sparkline history flows into the item; a <2-point series is dropped, not drawn degenerate")
func stocksHistoryMapping() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([
            stockRow("SPY", 100, 1, 1, history: [98, 99, 100]),
            stockRow("AAPL", 200, -1, -1, history: [200]), // too short to plot → dropped
            stockRow("NVDA", 300, 1, 1, history: nil),
        ]),
        now: stocksFixedNow
    )
    #expect(widget.data?.items.first?.history == [98, 99, 100])
    #expect(widget.data?.items[1].history == nil)
    #expect(widget.data?.items.last?.history == nil)
}

@Test("an empty batch (no tickers configured) maps to an honest empty widget")
func stocksEmptyMapping() {
    let widget = BridgeEventFactory.stocksWidget(from: .success([]), now: stocksFixedNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a batch where every symbol failed maps to unavailable, not a grid of dashes")
func stocksAllFailedMapping() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([stockRow("SPY", nil, nil, nil), stockRow("AAPL", nil, nil, nil)]),
        now: stocksFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
}

@Test("a missing credential maps to unavailable with guidance to add the API key")
func stocksCredentialsMissingMapping() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .failure(StockQuoteError.credentialsMissing), now: stocksFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.contains("Finnhub API key") == true)
}

@Test("a provider failure maps to a generic unavailable, never leaking the diagnostic")
func stocksProviderFailureMapping() {
    let widget = BridgeEventFactory.stocksWidget(
        from: .failure(StockQuoteError.providerFailed("HTTP 500")), now: stocksFixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    // The generic failure is not the credentials message and does not leak the raw diagnostic.
    #expect(widget.emptyMessage?.contains("Finnhub API key") == false)
    #expect(widget.emptyMessage?.contains("HTTP 500") == false)
}

@Test("the widget emits as a widget.data.changed event; a nil figure is omitted, not null")
func stocksEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.stocksWidget(
        from: .success([stockRow("SPY", 100.5, 2.25, 1.5), stockRow("???", nil, nil, nil)]),
        now: stocksFixedNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "stocks", widget: widget, id: "brevt_test00000128", timestamp: stocksFixedNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"stocks\""))
    #expect(json.contains("\"symbol\":\"SPY\""))
    #expect(json.contains("\"price\":100.5"))
    // The synthesized encoding omits the unresolved row's nil figures rather than writing null.
    #expect(!json.contains("\"price\":null"))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000128")
}
