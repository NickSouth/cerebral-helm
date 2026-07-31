// NIC-128: Yahoo chart request building and daily-close parsing for the tile sparkline.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the request targets Yahoo's 1-month daily chart with a User-Agent (no credential)")
func yahooRequestShape() throws {
    let request = try #require(YahooStockHistoryProvider.makeRequest(
        host: "https://query1.finance.yahoo.com", symbol: "AAPL"
    ))
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "query1.finance.yahoo.com")
    #expect(components.path == "/v8/finance/chart/AAPL")
    #expect(components.queryItems?.first(where: { $0.name == "range" })?.value == "1mo")
    #expect(components.queryItems?.first(where: { $0.name == "interval" })?.value == "1d")
    // The endpoint rejects the default client, so a User-Agent is set. There is no token anywhere.
    #expect(request.value(forHTTPHeaderField: "User-Agent")?.isEmpty == false)
}

@Test("parsing returns closes oldest→newest with null gaps dropped")
func yahooParsesCloses() throws {
    let json = Data("""
    { "chart": { "result": [ { "indicators": { "quote": [ { "close": [100.0, null, 102.5, 103.0] } ] } } ] } }
    """.utf8)
    let closes = try YahooStockHistoryProvider.parse(json)
    #expect(closes == [100.0, 102.5, 103.0]) // the null holiday/gap is dropped, never fabricated
}

@Test("a series with fewer than two real closes throws, so the tile omits the line")
func yahooTooFewPointsThrows() {
    let json = Data("""
    { "chart": { "result": [ { "indicators": { "quote": [ { "close": [100.0, null] } ] } } ] } }
    """.utf8)
    #expect(throws: StockQuoteError.self) {
        _ = try YahooStockHistoryProvider.parse(json)
    }
}

@Test("a missing result series throws providerFailed")
func yahooMissingResultThrows() {
    let json = Data(#"{ "chart": { "result": [] } }"#.utf8)
    #expect(throws: StockQuoteError.self) {
        _ = try YahooStockHistoryProvider.parse(json)
    }
}

@Test("malformed JSON throws providerFailed, never a fabricated series")
func yahooMalformedThrows() {
    #expect(throws: StockQuoteError.self) {
        _ = try YahooStockHistoryProvider.parse(Data("not json".utf8))
    }
}
#endif
