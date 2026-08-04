// Streaming the unread-mail count (Gmail integration, 2026-08-04).
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Samples the unread count on a slow cadence and emits one `mail.changed` event per tick.
///
/// **Slow on purpose.** Unlike the now-playing widget, which tracks something the user is actively
/// changing, an unread count moves when mail arrives — minutes apart at best. Five minutes keeps it
/// current enough to be believed without making this the noisiest client on the account. Each tick
/// is a *single* `labels.get`, which reads no message.
///
/// Deactivated while the dashboard is not visible (the shell flips `setActive` from occlusion
/// state), and reactivating emits immediately so returning to a hidden dashboard never shows a
/// count from an hour ago.
///
/// **Every failure state is distinct in the payload**, because the remedies differ and because a
/// count is exactly the kind of value a surface would otherwise render as a reassuring zero:
/// `not-connected` (connect it), `reconnect` (the grant lapsed — routine on a Testing-status
/// project), and `unavailable` (Gmail could not be reached).
public actor MailPublisher {
    private let provider: any MailProvider
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        provider: any MailProvider,
        intervalMs: Int = 5 * 60 * 1_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.provider = provider
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the count is
    /// present as soon as the dashboard is, rather than five minutes later.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickIfActive()
                try? await Task.sleep(nanoseconds: await self.interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    private var interval: UInt64 { intervalNanos }

    /// Occlusion control. Reactivating samples at once: a count the user is looking at should not
    /// be one from before they looked away.
    public func setActive(_ isActive: Bool) {
        let wasActive = active
        active = isActive
        if isActive, !wasActive {
            Task { await self.tick() }
        }
    }

    /// Samples now — after a connect, so the count appears immediately rather than on the next tick.
    public func refresh() async {
        await tick()
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        do {
            let summary = try await provider.unreadSummary()
            publish(
                state: "ready", unread: summary.count, capped: summary.isCapped,
                scope: summary.scope.rawValue, reason: nil
            )
        } catch let error as MailError {
            switch error {
            case .notConnected:
                publish(state: "not-connected", unread: nil, reason: nil)
            case .reconnectRequired:
                publish(
                    state: "reconnect", unread: nil,
                    reason: "Gmail needs reconnecting — Settings → Setup."
                )
            case let .providerFailed(detail):
                publish(state: "unavailable", unread: nil, reason: detail)
            }
        } catch {
            publish(state: "unavailable", unread: nil, reason: error.localizedDescription)
        }
    }

    private func publish(
        state: String, unread: Int?, capped: Bool = false, scope: String? = nil, reason: String?
    ) {
        let event = BridgeEventFactory.mailChangedEvent(
            state: state, unread: unread, unreadCapped: capped, unreadScope: scope, reason: reason,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        )
        guard let data = try? BridgeMessageCoding.encoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        emit(json)
    }
}
#endif
