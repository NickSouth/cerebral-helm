// Streaming active-repos widget events (NIC-131) — the widget-liveness blueprint's
// first live producer.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Samples the projects root on a fixed cadence and emits one `widget.data.changed`
/// event for the `repositories` widget per tick (NIC-131).
///
/// Mirrors ``SystemStatusPublisher``'s battery/responsiveness discipline: sampling is a
/// handful of cheap filesystem reads (directory listing + `HEAD` files) every
/// `intervalMs` (default 5 s, since branches change slowly), and the loop is
/// **deactivated while the dashboard is not visible** — the shell flips `setActive` from
/// the dashboard window's occlusion state. Reactivation emits immediately, so the widget
/// is live the moment it becomes visible again. The reader itself never spawns a process.
public actor ActiveReposPublisher {
    private let provider: any ActiveReposProvider
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        provider: any ActiveReposProvider = FileSystemActiveReposProvider(),
        intervalMs: Int = 5000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.provider = provider
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the
    /// widget populates as soon as the stream starts rather than after one interval.
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

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh snapshot
    /// immediately instead of waiting out the current interval.
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
        let result: Swift.Result<[RepoStatus], Error>
        do {
            result = .success(try provider.activeRepositories())
        } catch {
            result = .failure(error)
        }
        let widget = BridgeEventFactory.repositoriesWidget(from: result, now: Date())
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: "repositories",
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
