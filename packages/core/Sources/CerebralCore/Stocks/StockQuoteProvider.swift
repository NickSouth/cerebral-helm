import Foundation

/// A single stock quote's day figures for the Executive "Stocks" widget (NIC-128). Produced by a
/// ``StockQuoteProvider`` for one symbol and paired with that symbol by the live producer
/// (Increment 6). Pure figures — the symbol lives on the request and on ``StockQuoteResult``, so a
/// failed lookup can still render its ticker rather than a fabricated price. All three values are
/// day status relative to the previous close.
public struct StockQuote: Equatable, Sendable {
    /// Latest trade price.
    public let price: Double
    /// Absolute change on the day (vs previous close).
    public let change: Double
    /// Percent change on the day.
    public let changePercent: Double

    public init(price: Double, change: Double, changePercent: Double) {
        self.price = price
        self.change = change
        self.changePercent = changePercent
    }
}

/// One symbol's outcome in a batch of quotes (NIC-128): the ticker plus its figures, or a nil
/// quote when that symbol couldn't be resolved. The symbol is always present so an unresolved row
/// still renders its ticker with a muted "—" instead of a fabricated price. The live producer
/// (Increment 6) builds one per configured ticker; the event mapping turns each into a widget row.
public struct StockQuoteResult: Equatable, Sendable {
    public let symbol: String
    public let quote: StockQuote?
    /// Recent daily closing prices (oldest → newest, ~1 month) for the tile's sparkline, or nil
    /// when the history source is unavailable. Best-effort and decorative — it comes from a
    /// separate provider than the quote, so a history miss never blocks the price/change; the
    /// tile simply omits the line. Never fabricated.
    public let history: [Double]?

    public init(symbol: String, quote: StockQuote?, history: [Double]? = nil) {
        self.symbol = symbol
        self.quote = quote
        self.history = history
    }
}

/// Why a stock quote could not be produced. Provider-neutral and coarse: the event mapping
/// degrades a whole-widget failure to an honest `unavailable`, distinguishing only a missing
/// credential (so the widget can say "add your API key") from a provider/network failure.
/// FR-CFG-03/FR-SAF-07: a missing secret becomes honest guidance, never a fabricated quote.
/// ``credentialsMissing`` is thrown by the publisher when the Keychain reference is unbound
/// (Increment 6); ``unknownSymbol`` is a per-symbol miss (the provider responded but the symbol
/// isn't a real ticker); ``providerFailed`` is a network/parse failure.
public enum StockQuoteError: Error, Equatable, Sendable {
    /// No API credential is configured — the widget should guide the user to add one.
    case credentialsMissing
    /// The provider responded but the symbol isn't a recognised ticker.
    case unknownSymbol
    /// The quote provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that fetches the current day quote for one symbol (NIC-128). Provider-neutral and
/// credential-driven: the caller (the ``StocksPublisher``, Increment 6) resolves the API token
/// from the Keychain and passes it in, so this contract never touches the secret store. Async
/// because a real provider performs a network fetch (Finnhub, Increment 3); the mock resolves
/// synchronously. Throws ``StockQuoteError`` on failure — the publisher folds a per-symbol failure
/// into a nil-quote row and a whole-widget failure into an honest `unavailable`.
public protocol StockQuoteProvider: Sendable {
    func quote(symbol: String, apiToken: String) async throws -> StockQuote
}

/// A fixed-outcome ``StockQuoteProvider`` for pre-Mac builds and tests: it ignores the symbol and
/// token and always yields the quote (or throws the error) it was constructed with.
public struct MockStockQuoteProvider: StockQuoteProvider {
    private let outcome: Result<StockQuote, StockQuoteError>

    public init(quote: StockQuote) {
        self.outcome = .success(quote)
    }

    public init(error: StockQuoteError) {
        self.outcome = .failure(error)
    }

    public func quote(symbol: String, apiToken: String) async throws -> StockQuote {
        try outcome.get()
    }
}

/// Port that fetches a symbol's recent daily closing prices for the tile sparkline (NIC-128),
/// oldest → newest. Provider-neutral and **keyless** — the sparkline is a decorative enrichment,
/// so a real adapter uses a free, no-credential source (Yahoo, Increment: sparkline) separate
/// from the authoritative quote provider. Async because the real fetch is network; the mock
/// resolves synchronously. Throws on failure — the publisher treats any error as "no history"
/// (a nil sparkline), never blocking the quote.
public protocol StockHistoryProvider: Sendable {
    func dailyCloses(symbol: String) async throws -> [Double]
}

/// A fixed-outcome ``StockHistoryProvider`` for pre-Mac builds and tests.
public struct MockStockHistoryProvider: StockHistoryProvider {
    private let outcome: Result<[Double], StockQuoteError>

    public init(closes: [Double]) {
        self.outcome = .success(closes)
    }

    public init(error: StockQuoteError) {
        self.outcome = .failure(error)
    }

    public func dailyCloses(symbol: String) async throws -> [Double] {
        try outcome.get()
    }
}
