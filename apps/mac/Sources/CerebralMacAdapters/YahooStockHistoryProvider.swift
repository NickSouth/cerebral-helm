// Keyless daily-close history for the Stocks tile sparkline (NIC-128).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Fetches ~1 month of daily closing prices for a symbol from Yahoo Finance's public chart
/// endpoint (`query1.finance.yahoo.com/v8/finance/chart/<symbol>?range=1mo&interval=1d`) with
/// `URLSession`. **Keyless** — the sparkline is a decorative enrichment, so it uses a free,
/// no-credential source separate from the authoritative Finnhub quote. The endpoint is
/// unofficial, so any transport, non-2xx, decode, or empty-series outcome throws
/// ``StockQuoteError/providerFailed(_:)`` and the publisher degrades to "no sparkline" — the
/// price and day change (from Finnhub) are unaffected.
///
/// Closes are returned oldest → newest with gaps (holidays / an in-progress day arrive as
/// `null`) dropped, so the sparkline is a clean line of real closes, never a fabricated point.
public struct YahooStockHistoryProvider: StockHistoryProvider {
    private let session: URLSession
    private let host: String

    public init(
        session: URLSession? = nil,
        host: String = "https://query1.finance.yahoo.com",
        resourceTimeout: TimeInterval = 15
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
    }

    public func dailyCloses(symbol: String) async throws -> [Double] {
        guard let request = Self.makeRequest(host: host, symbol: symbol) else {
            throw StockQuoteError.providerFailed("Could not build the history request URL.")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw StockQuoteError.providerFailed("The history service returned an unsuccessful response.")
            }
            return try Self.parse(data)
        } catch let error as StockQuoteError {
            throw error
        } catch {
            throw StockQuoteError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the chart request for one month of daily candles. A `User-Agent` header is set
    /// because the endpoint rejects the default client. The symbol is percent-encoded by
    /// `URLComponents`; there is no credential to leak.
    static func makeRequest(host: String, symbol: String) -> URLRequest? {
        guard var components = URLComponents(string: "\(host)/v8/finance/chart/\(symbol)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "range", value: "1mo"),
            URLQueryItem(name: "interval", value: "1d")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Yahoo's chart shape (only the fields we read). `close` may contain `null` for gaps.
    private struct Response: Decodable {
        struct Chart: Decodable {
            struct ResultEntry: Decodable {
                struct Indicators: Decodable {
                    struct Quote: Decodable { let close: [Double?]? }
                    let quote: [Quote]
                }
                let indicators: Indicators
            }
            let result: [ResultEntry]?
        }
        let chart: Chart
    }

    /// Decodes the chart payload into a clean oldest → newest array of real closes (nulls dropped).
    /// An empty series or a missing result throws ``providerFailed`` so the tile omits the line.
    static func parse(_ data: Data) throws -> [Double] {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw StockQuoteError.providerFailed("Could not parse the history response.")
        }
        guard
            let result = decoded.chart.result?.first,
            let closes = result.indicators.quote.first?.close
        else {
            throw StockQuoteError.providerFailed("The history response had no price series.")
        }
        let cleaned = closes.compactMap { $0 }
        guard cleaned.count >= 2 else {
            throw StockQuoteError.providerFailed("The history response had too few points to plot.")
        }
        return cleaned
    }
}
#endif
