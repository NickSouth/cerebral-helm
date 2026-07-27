// Streaming Stocks widget events (NIC-128) — the Executive left-slot producer.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// Resolves the user's tracked tickers and the Finnhub API token, fetches a quote per symbol, and
/// emits one `widget.data.changed` event for the `stocks` widget per tick (NIC-128). The dashboard
/// folds it into `liveWidgets`, which the Executive left rail renders (NIC-131 blueprint).
///
/// Mirrors ``ReleasesPublisher``'s battery/visibility discipline on a **slow cadence** (default
/// 5 min — quotes change often but each tick makes one network request per ticker, and the free
/// tier is rate-limited): the loop is deactivated while the dashboard is not visible and
/// reactivation emits immediately. The ticker list and token are read **per tick**, so a Settings
/// edit (a new ticker or a just-entered key) takes effect on the next sample without a relaunch;
/// the shell also calls ``refresh()`` on those edits so the change is immediate.
///
/// Honest states (never fabricated): an empty ticker list → the widget's "add tickers" prompt; no
/// stored key → an "add your Finnhub key" unavailable; a single symbol that fails to resolve → a
/// nil-quote row (the tile shows "—") while the others render; a whole-batch failure → unavailable.
public actor StocksPublisher {
    private let tickers: @Sendable () -> [String]
    private let secretStore: any SecretStoreManaging
    private let provider: any StockQuoteProvider
    private let history: (any StockHistoryProvider)?
    private let reference: String
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        tickers: @escaping @Sendable () -> [String],
        secretStore: any SecretStoreManaging,
        provider: any StockQuoteProvider,
        history: (any StockHistoryProvider)? = nil,
        reference: String = "finnhub_api_key",
        intervalMs: Int = 300_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.tickers = tickers
        self.secretStore = secretStore
        self.provider = provider
        self.history = history
        self.reference = reference
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the widget
    /// populates as soon as the stream starts rather than after one (long) interval.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickIfActive()
                try? await Task.sleep(nanoseconds: self.intervalNanos)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Emit a fresh sample now, regardless of cadence — used when the user just edited their
    /// tickers or stored the Finnhub key (NIC-128), so the widget updates at once instead of
    /// waiting out the interval. The list and token are re-read this tick.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately
    /// instead of waiting out the current interval.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick()
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        let symbols = tickers()
        let result: Swift.Result<[StockQuoteResult], Error>
        if symbols.isEmpty {
            // No configured tickers → an honest empty widget ("add tickers"), never a key prompt.
            result = .success([])
        } else {
            do {
                let token = try await secretStore.readValue(reference: reference)
                var rows: [StockQuoteResult] = []
                for symbol in symbols {
                    // The sparkline history is a best-effort, keyless enrichment from a separate
                    // provider: a failure (or no provider) yields nil so the tile just omits the
                    // line — it never blocks the quote or fails the widget.
                    let closes = (try? await history?.dailyCloses(symbol: symbol)) ?? nil
                    do {
                        let quote = try await provider.quote(symbol: symbol, apiToken: token)
                        rows.append(StockQuoteResult(symbol: symbol, quote: quote, history: closes))
                    } catch {
                        // A single symbol failing (unknown/transport) is honest per-row: a nil
                        // quote renders "—" on that tile and never fails the whole widget.
                        rows.append(StockQuoteResult(symbol: symbol, quote: nil, history: closes))
                    }
                }
                result = .success(rows)
            } catch {
                // A missing keychain entry → guide the user to add the key; any other failure
                // (denied keychain) → a generic honest unavailable.
                if let native = error as? NativeCapabilityError, case .notFound = native {
                    result = .failure(StockQuoteError.credentialsMissing)
                } else {
                    result = .failure(error)
                }
            }
        }

        let widget = BridgeEventFactory.stocksWidget(from: result, now: Date())
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: "stocks",
            widget: widget,
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }
}
#endif
