import Foundation
import Testing

import CerebralCore

/// NIC-128 Increment 2: the portable stock-quote contract — a provider-neutral ``StockQuote`` +
/// ``StockQuoteProvider`` port with a fixed-outcome mock. The real Finnhub fetch lands in the Mac
/// adapter (Increment 3).

@Test("the mock quote provider yields its constructed quote, ignoring symbol and token")
func stockQuoteMockYieldsQuote() async throws {
    let provider = MockStockQuoteProvider(
        quote: StockQuote(price: 543.21, change: 3.24, changePercent: 0.6)
    )
    let quote = try await provider.quote(symbol: "SPY", apiToken: "ignored")
    #expect(quote.price == 543.21)
    #expect(quote.change == 3.24)
    #expect(quote.changePercent == 0.6)
}

@Test("the mock quote provider throws its constructed error")
func stockQuoteMockThrowsError() async {
    let provider = MockStockQuoteProvider(error: .credentialsMissing)
    await #expect(throws: StockQuoteError.credentialsMissing) {
        try await provider.quote(symbol: "SPY", apiToken: "")
    }
}

@Test("StockQuoteError distinguishes its cases")
func stockQuoteErrorCasesAreDistinct() {
    #expect(StockQuoteError.credentialsMissing != StockQuoteError.unknownSymbol)
    #expect(StockQuoteError.unknownSymbol != StockQuoteError.providerFailed("boom"))
    #expect(StockQuoteError.providerFailed("a") == StockQuoteError.providerFailed("a"))
}

@Test("a StockQuoteResult keeps its symbol even when the quote is nil")
func stockQuoteResultKeepsSymbolOnFailure() {
    let resolved = StockQuoteResult(
        symbol: "SPY", quote: StockQuote(price: 1, change: 0, changePercent: 0)
    )
    let failed = StockQuoteResult(symbol: "???", quote: nil)
    #expect(resolved.symbol == "SPY")
    #expect(resolved.quote != nil)
    #expect(failed.symbol == "???")
    #expect(failed.quote == nil)
    #expect(resolved.history == nil) // history defaults to nil (best-effort, absent unless set)
}

@Test("the mock history provider yields its constructed closes, and a result can carry them")
func stockHistoryMockAndResult() async throws {
    let provider = MockStockHistoryProvider(closes: [1, 2, 3])
    #expect(try await provider.dailyCloses(symbol: "SPY") == [1, 2, 3])

    let withHistory = StockQuoteResult(
        symbol: "SPY", quote: StockQuote(price: 3, change: 1, changePercent: 1), history: [1, 2, 3]
    )
    #expect(withHistory.history == [1, 2, 3])
}

@Test("the mock history provider throws its constructed error")
func stockHistoryMockThrows() async {
    let provider = MockStockHistoryProvider(error: .providerFailed("boom"))
    await #expect(throws: StockQuoteError.self) {
        _ = try await provider.dailyCloses(symbol: "SPY")
    }
}
