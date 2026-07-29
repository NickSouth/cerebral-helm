// Streaming the School Canvas widgets (NIC-132) from the local scrape store.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Reads the latest Canvas scrape from the local store and emits the two School widgets' live data —
/// one `widget.data.changed` for `courses` and one for `deadlines` — through ``BridgeEventFactory``,
/// which applies the freshness/staleness policy (NIC-132). The ingest endpoint calls ``refresh()``
/// the moment a new scrape is persisted, so the widgets update immediately; a slow cadence otherwise
/// keeps the "data age" label and the ready→stale transition honest as time passes without a scrape.
///
/// The store read is the only work per tick, so this stays lightweight. Mirrors the sibling
/// producers' visibility discipline: deactivated while the dashboard is hidden, and resuming emits a
/// fresh sample immediately. A store read failure maps to an honest "unavailable" widget, never a
/// fabricated one.
public actor CanvasWidgetPublisher {
    private let store: any CanvasSnapshotStore
    private let staleAfter: TimeInterval
    private let intervalNanos: UInt64
    private let now: @Sendable () -> Date
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        store: any CanvasSnapshotStore,
        staleAfter: TimeInterval = 6 * 3600,
        intervalMs: Int = 600_000,
        now: @escaping @Sendable () -> Date = { Date() },
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.store = store
        self.staleAfter = staleAfter
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.now = now
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately so the widgets populate
    /// from any already-stored scrape as soon as the stream starts.
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

    /// Emit a fresh sample now — called by the ingest endpoint the instant a new scrape is persisted,
    /// so the widgets don't wait out the cadence.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal; resuming emits immediately.
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
        let result = Swift.Result { try store.load() }
        let sampledAt = now()
        emitWidget(
            widgetId: "courses",
            widget: BridgeEventFactory.canvasCoursesWidget(from: result, now: sampledAt, staleAfter: staleAfter)
        )
        emitWidget(
            widgetId: "deadlines",
            widget: BridgeEventFactory.canvasDeadlinesWidget(from: result, now: sampledAt, staleAfter: staleAfter)
        )
    }

    private func emitWidget<Widget: Encodable>(widgetId: String, widget: Widget) {
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: widgetId, widget: widget, id: BridgeEventFactory.newEventID(), timestamp: now()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }
}
#endif
