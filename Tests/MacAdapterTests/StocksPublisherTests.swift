// NIC-128 Increment 6: streaming the stocks widget as widget.data.changed events, keyed off the
// user's tracked tickers (settings) and a Keychain-resolved Finnhub token.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralTools

private final class StockEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

private func waitForStocks(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test("with tickers and a stored key the publisher emits a ready stocks widget on cadence")
func stocksPublisherEmitsReady() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY", "AAPL"] },
        secretStore: MockSecretStore(values: ["finnhub_api_key": "tok"]),
        provider: MockStockQuoteProvider(quote: StockQuote(price: 543.21, change: 3.24, changePercent: 0.6)),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .widgetDataChanged)
    #expect(collector.all[0].contains("\"widgetId\":\"stocks\""))
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"symbol\":\"SPY\""))
    #expect(collector.all[0].contains("\"symbol\":\"AAPL\""))
    // The token is never part of the emitted event.
    #expect(!collector.all[0].contains("tok"))
}

@Test("an empty ticker list emits an honest empty widget, never a key prompt")
func stocksPublisherEmitsEmptyForNoTickers() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { [] }, // the user cleared their tickers
        secretStore: MockSecretStore(), // no key — but the empty list takes precedence
        provider: MockStockQuoteProvider(quote: StockQuote(price: 1, change: 0, changePercent: 0)),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"empty\""))
    #expect(!collector.all[0].contains("Finnhub API key")) // empty-list, not a key prompt
}

@Test("with tickers but no stored key the publisher emits an honest add-your-key state")
func stocksPublisherEmitsCredentialsMissing() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY"] },
        secretStore: MockSecretStore(), // empty — no key bound
        provider: MockStockQuoteProvider(quote: StockQuote(price: 1, change: 0, changePercent: 0)),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("Finnhub API key"))
}

@Test("when every symbol fails the publisher emits a generic unavailable, never fabricated quotes")
func stocksPublisherEmitsGenericFailure() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY", "AAPL"] },
        secretStore: MockSecretStore(values: ["finnhub_api_key": "tok"]),
        provider: MockStockQuoteProvider(error: .providerFailed("HTTP 500")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(!collector.all[0].contains("Finnhub API key")) // not the credentials message
    #expect(!collector.all[0].contains("HTTP 500")) // raw diagnostic not leaked
}

@Test("the sparkline history is included in the event when the history provider succeeds")
func stocksPublisherIncludesHistory() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY"] },
        secretStore: MockSecretStore(values: ["finnhub_api_key": "tok"]),
        provider: MockStockQuoteProvider(quote: StockQuote(price: 100, change: 1, changePercent: 1)),
        history: MockStockHistoryProvider(closes: [95, 97, 100]),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"history\":[95,97,100]"))
}

@Test("a history-provider failure still yields a ready widget with no sparkline (best-effort)")
func stocksPublisherHistoryFailureDegrades() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY"] },
        secretStore: MockSecretStore(values: ["finnhub_api_key": "tok"]),
        provider: MockStockQuoteProvider(quote: StockQuote(price: 100, change: 1, changePercent: 1)),
        history: MockStockHistoryProvider(error: .providerFailed("boom")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"ready\"")) // the quote still renders
    #expect(!collector.all[0].contains("\"history\"")) // the sparkline is simply omitted
}

@Test("a paused stocks publisher emits nothing; resuming emits immediately")
func stocksPublisherPauseResume() async throws {
    let collector = StockEventCollector()
    let publisher = StocksPublisher(
        tickers: { ["SPY"] },
        secretStore: MockSecretStore(values: ["finnhub_api_key": "tok"]),
        provider: MockStockQuoteProvider(quote: StockQuote(price: 1, change: 0, changePercent: 0)),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForStocks(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitForStocks(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
