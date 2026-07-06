// Streaming system-status events (NIC-81b, MAC-ADAPTER-3).
#if canImport(AppKit)
import Foundation
import CerebralRuntimeHost
import CerebralTools

/// Samples the shared ``MacSystemStatusCapability`` on a fixed cadence and emits
/// one `system.status.changed` bridge event per tick (FR-UI-04, FR-SHL-06).
///
/// Battery/responsiveness discipline (MAC-ADAPTER-3 AC): the sampling calls are a
/// handful of cheap syscalls every `intervalMs` (default 2 s), and the loop is
/// **deactivated while the dashboard is not visible** — the shell flips
/// `setActive` from the dashboard window's occlusion state, so a hidden or
/// fully-covered dashboard costs nothing. Reactivation emits immediately, so the
/// panel is live the moment it becomes visible again.
///
/// The publisher shares the capability actor with the one-shot
/// `system.status.read` tool, so both see the same rate-metric delta state.
public actor SystemStatusPublisher {
    private let status: MacSystemStatusCapability
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        status: MacSystemStatusCapability,
        intervalMs: Int = 2000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.status = status
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately —
    /// rate metrics honestly report `loading` until their second sample.
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

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh
    /// snapshot immediately instead of waiting out the current interval.
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
        let snapshot = await status.snapshot()
        let event = BridgeEventFactory.systemStatusEvent(
            Self.payload(snapshot),
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }

    public static func payload(_ snapshot: SystemStatusSnapshot) -> BridgeEventFactory.SystemMetricsPayload {
        func channel(_ source: SystemStatusChannel, unit: String?) -> BridgeEventFactory.SystemMetricsChannel {
            BridgeEventFactory.SystemMetricsChannel(
                availability: source.availability.rawValue,
                value: source.value,
                unit: unit,
                sampledAt: source.sampledAt
            )
        }
        return BridgeEventFactory.SystemMetricsPayload(
            cpu: channel(snapshot.cpu, unit: "percent"),
            memory: channel(snapshot.memory, unit: "percent"),
            network: BridgeEventFactory.SystemMetricsNetworkChannel(
                availability: snapshot.network.availability.rawValue,
                uploadMbps: snapshot.network.uploadMbps,
                downloadMbps: snapshot.network.downloadMbps,
                unit: "mbps",
                sampledAt: snapshot.network.sampledAt
            ),
            battery: BridgeEventFactory.SystemMetricsBatteryChannel(
                availability: snapshot.battery.availability.rawValue,
                value: snapshot.battery.percent,
                charging: snapshot.battery.isCharging,
                pluggedIn: snapshot.battery.isPluggedIn,
                unit: "percent",
                sampledAt: snapshot.battery.sampledAt
            ),
            display: channel(snapshot.display, unit: nil)
        )
    }
}
#endif
