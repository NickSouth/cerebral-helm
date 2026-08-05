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
    /// CPU's smoothing window (NIC-158). At a 2 s cadence from a 10% idle baseline this reaches the
    /// panel's yellow threshold (60%) after ~24 s of sustained full load and red (85%) after ~54 s,
    /// while a single 2 s spike to 100% moves the bar only ~6 points — so "red" reliably means
    /// "this has been going on for a while", which is the only reading worth acting on.
    private static let cpuTimeConstant: TimeInterval = 30

    /// Memory's window is much shorter: the usage percentage is already stable (it does not spike
    /// the way CPU does), so this exists to make the bar glide rather than to reject transients.
    private static let memoryTimeConstant: TimeInterval = 10

    private let status: MacSystemStatusCapability
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true
    private var cpuAverage = ExponentialMovingAverage(timeConstant: SystemStatusPublisher.cpuTimeConstant)
    private var memoryAverage = ExponentialMovingAverage(timeConstant: SystemStatusPublisher.memoryTimeConstant)

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
        if !nowActive && wasActive {
            // Nothing is sampled while the dashboard is hidden, so there is no history to
            // continue — the machine's load over that gap is simply unknown. Drop it and let the
            // resume tick re-seed from a real reading (NIC-158). Without this, the first bar the
            // user sees on return would be blended with however the machine looked minutes ago.
            cpuAverage.reset()
            memoryAverage.reset()
        }
        if nowActive && !wasActive {
            await tick()
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        let snapshot = smoothed(await status.snapshot())
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

    /// Replace the CPU and memory readings with their time-averaged values (NIC-158), leaving every
    /// other channel — and both channels' availability, timestamp, and memory's pressure level —
    /// exactly as sampled.
    ///
    /// Only the **streamed** values are smoothed. The one-shot `system.status.read` tool reads the
    /// capability directly and keeps reporting the instantaneous figure, which is what a tool
    /// contract should say. Battery, network, and display are point-in-time facts with nothing to
    /// average, and memory pressure arrives already debounced by the kernel — double-filtering a
    /// value someone else smoothed is how an indicator starts lying.
    func smoothed(_ snapshot: SystemStatusSnapshot) -> SystemStatusSnapshot {
        SystemStatusSnapshot(
            cpu: Self.smooth(snapshot.cpu, with: &cpuAverage),
            memory: Self.smooth(snapshot.memory, with: &memoryAverage),
            network: snapshot.network,
            battery: snapshot.battery,
            display: snapshot.display
        )
    }

    private static func smooth(
        _ channel: SystemStatusChannel, with average: inout ExponentialMovingAverage
    ) -> SystemStatusChannel {
        guard let sample = usableSample(channel.availability, channel.value, channel.sampledAt) else {
            average.reset()
            return channel
        }
        return SystemStatusChannel(
            availability: channel.availability,
            value: average.update(sample.value, at: sample.sampledAt),
            sampledAt: channel.sampledAt
        )
    }

    private static func smooth(
        _ channel: SystemStatusMemoryChannel, with average: inout ExponentialMovingAverage
    ) -> SystemStatusMemoryChannel {
        guard let sample = usableSample(channel.availability, channel.value, channel.sampledAt) else {
            average.reset()
            // The pressure level survives — it is sampled independently of the percentage, so an
            // unreadable percentage must not take the bar's colour signal down with it.
            return channel
        }
        return SystemStatusMemoryChannel(
            availability: channel.availability,
            value: average.update(sample.value, at: sample.sampledAt),
            pressure: channel.pressure,
            sampledAt: channel.sampledAt
        )
    }

    /// A reading worth folding into an average: genuinely available, with both a value and the
    /// timestamp the weighting needs. Anything else — `loading` (CPU's first sample, which has no
    /// delta yet), `unavailable`, or a stale/disconnected reading — is not a fresh measurement of
    /// the machine and must reset the history rather than extend it.
    private static func usableSample(
        _ availability: MetricAvailability, _ value: Double?, _ sampledAt: Date?
    ) -> (value: Double, sampledAt: Date)? {
        guard availability == .available, let value, let sampledAt else { return nil }
        return (value, sampledAt)
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
            memory: BridgeEventFactory.SystemMetricsMemoryChannel(
                availability: snapshot.memory.availability.rawValue,
                value: snapshot.memory.value,
                // nil stays nil across the wire — the dashboard falls back to thresholding the
                // percentage rather than being handed a fabricated level (NIC-158).
                pressure: snapshot.memory.pressure?.rawValue,
                unit: "percent",
                sampledAt: snapshot.memory.sampledAt
            ),
            network: BridgeEventFactory.SystemMetricsNetworkChannel(
                availability: snapshot.network.availability.rawValue,
                linkMbps: snapshot.network.linkMbps,
                wifiPower: snapshot.network.power.rawValue,
                signalRssi: snapshot.network.signalRssi,
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
