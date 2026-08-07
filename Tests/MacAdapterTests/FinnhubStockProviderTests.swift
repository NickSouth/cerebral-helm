// NIC-128: Finnhub request building and quote parsing (header auth, unknown-symbol sentinel).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the request targets Finnhub's quote endpoint with the token in the header, not the URL")
func finnhubRequestCarriesTokenInHeader() throws {
    let request = try #require(FinnhubStockProvider.makeRequest(
        host: "https://finnhub.io", symbol: "AAPL", apiToken: "secret-token-123"
    ))
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "finnhub.io")
    #expect(components.path == "/api/v1/quote")
    #expect(components.queryItems?.first(where: { $0.name == "symbol" })?.value == "AAPL")

    // The token rides the header — never the URL, so it can't leak into logs.
    #expect(request.value(forHTTPHeaderField: "X-Finnhub-Token") == "secret-token-123")
    #expect(!url.absoluteString.contains("secret-token-123"))
}

@Test("a normal quote parses its price, change, and percent from c/d/dp")
func finnhubParsesQuote() throws {
    let json = Data("""
    { "c": 261.74, "d": 2.24, "dp": 0.8632, "h": 263.31, "l": 260.68, "o": 261.07, "pc": 259.5, "t": 1582641000 }
    """.utf8)
    let quote = try FinnhubStockProvider.parse(json)
    #expect(quote.price == 261.74)
    #expect(quote.change == 2.24)
    #expect(quote.changePercent == 0.8632)
}

@Test("an all-zero body (Finnhub's unknown-symbol sentinel) throws unknownSymbol, never a $0 quote")
func finnhubUnknownSymbol() {
    // Finnhub returns c=0 and pc=0 (with d/dp null) for a ticker it doesn't recognise.
    let json = Data("""
    { "c": 0, "d": null, "dp": null, "h": 0, "l": 0, "o": 0, "pc": 0, "t": 0 }
    """.utf8)
    #expect(throws: StockQuoteError.unknownSymbol) {
        _ = try FinnhubStockProvider.parse(json)
    }
}

@Test("absent d/dp on a real quote are derived from c and pc, never guessed")
func finnhubDerivesChangeWhenAbsent() throws {
    // A valid quote (non-zero prices) where the change fields are null: derive from c − pc.
    let json = Data("""
    { "c": 110, "d": null, "dp": null, "pc": 100 }
    """.utf8)
    let quote = try FinnhubStockProvider.parse(json)
    #expect(quote.price == 110)
    #expect(quote.change == 10) // 110 − 100
    #expect(quote.changePercent == 10) // (110 − 100) / 100 × 100
}

@Test("malformed JSON throws providerFailed, never a fabricated quote")
func finnhubParseFailure() {
    #expect(throws: StockQuoteError.self) {
        _ = try FinnhubStockProvider.parse(Data("not json".utf8))
    }
}
#endif
