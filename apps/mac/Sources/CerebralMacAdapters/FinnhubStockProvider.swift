// Real-time stock quotes from Finnhub (NIC-128).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Fetches a single symbol's day quote from Finnhub (`finnhub.io`) with `URLSession`. The API
/// token is supplied per call (resolved from the Keychain by the ``StocksPublisher``, Increment 6)
/// and sent in the **`X-Finnhub-Token` header** — never in the URL or query string, so it can't
/// leak into logs or diagnostics (FR-OBS-03). Mirrors the read-only ephemeral-`URLSession` pattern
/// the weather + releases adapters use.
///
/// Endpoint is `GET /api/v1/quote?symbol=<symbol>`: the free tier (60 req/min) returns the day
/// figures `c` (current price), `d` (change), `dp` (percent change), and `pc` (previous close).
/// Finnhub returns an **all-zero** body (`c` and `pc` both 0) for an unrecognised symbol — that is
/// mapped to ``StockQuoteError/unknownSymbol`` rather than a fabricated `$0.00` quote. Any
/// transport, non-2xx, or decode failure throws ``StockQuoteError/providerFailed(_:)`` so the
/// widget degrades to an honest "unavailable" — never a made-up price.
public struct FinnhubStockProvider: StockQuoteProvider {
    private let session: URLSession
    private let host: String

    public init(
        session: URLSession? = nil,
        host: String = "https://finnhub.io",
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

    public func quote(symbol: String, apiToken: String) async throws -> StockQuote {
        guard let request = Self.makeRequest(host: host, symbol: symbol, apiToken: apiToken) else {
            throw StockQuoteError.providerFailed("Could not build the quote request URL.")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw StockQuoteError.providerFailed("The quote service returned an unsuccessful response.")
            }
            return try Self.parse(data)
        } catch let error as StockQuoteError {
            throw error
        } catch {
            throw StockQuoteError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the quote request. The token rides the `X-Finnhub-Token` header, deliberately NOT the
    /// URL — so the secret never appears in a logged/cached request URL. The `symbol` is not a
    /// secret, so it stays in the query string (percent-encoded by `URLComponents`).
    static func makeRequest(host: String, symbol: String, apiToken: String) -> URLRequest? {
        guard var components = URLComponents(string: "\(host)/api/v1/quote") else { return nil }
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiToken, forHTTPHeaderField: "X-Finnhub-Token")
        return request
    }

    /// Finnhub's `/quote` shape. `d`/`dp` are optional because Finnhub sends them as `null` for an
    /// unrecognised symbol; `c`/`pc` are always present (0 for an unknown symbol). The property
    /// names match Finnhub's single-letter JSON keys, so no `CodingKeys` are needed.
    private struct Response: Decodable {
        /// Current price.
        let c: Double
        /// Absolute change on the day (null for an unknown symbol).
        let d: Double?
        /// Percent change on the day (null for an unknown symbol).
        let dp: Double?
        /// Previous close.
        let pc: Double
    }

    /// Decodes a Finnhub `/quote` payload into a ``StockQuote``. An all-zero body (`c` and `pc`
    /// both 0) is Finnhub's sentinel for a symbol it doesn't recognise → ``unknownSymbol``, never a
    /// fabricated `$0` quote. When `d`/`dp` are absent (they can be null) but the prices are real,
    /// the change is derived arithmetically from `c` and `pc` (Finnhub's own definition) rather
    /// than guessed. Malformed JSON throws ``providerFailed``.
    static func parse(_ data: Data) throws -> StockQuote {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw StockQuoteError.providerFailed("Could not parse the quote response.")
        }

        if decoded.c == 0, decoded.pc == 0 {
            throw StockQuoteError.unknownSymbol
        }

        let change = decoded.d ?? (decoded.c - decoded.pc)
        let changePercent = decoded.dp ?? (decoded.pc != 0 ? ((decoded.c - decoded.pc) / decoded.pc) * 100 : 0)
        return StockQuote(price: decoded.c, change: change, changePercent: changePercent)
    }
}
#endif
