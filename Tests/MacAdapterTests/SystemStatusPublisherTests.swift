// NIC-81b (MAC-ADAPTER-3): streaming system-status events.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
// @testable so the smoothing (NIC-158) can be driven at exact timestamps: `smoothed(_:)` is
// internal, and the snapshot channels' memberwise initializers are internal too. Widening either
// to public purely for tests would put a seam in the production API that nothing ships against.
@testable import CerebralMacAdapters
import CerebralTools

/// A steady scripted source: constant counters advancing each call, so every
/// tick after the first produces available readings.
private final class SteadySource: SystemMetricSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: Double = 0

    func cpuTicks() -> CPUTicksSample? {
        lock.lock(); defer { lock.unlock() }
        ticks += 100
        return CPUTicksSample(busyTicks: ticks / 4, totalTicks: ticks)
    }

    func memory() -> MemorySample? { MemorySample(usedBytes: 8, totalBytes: 16) }

    func memoryPressure() -> MemoryPressureLevel? { .normal }

    func wifiLinkMbps() -> Double? { 866 }

    func wifiState() -> WiFiStateSample? { WiFiStateSample(power: .on, rssi: -59) }

    func battery() -> BatterySample? { BatterySample(percent: 76, isCharging: false, isPluggedIn: true) }
    func displayCount() -> Int? { 2 }
}

/// A host whose pressure level cannot be read (a future OS value, or a failed sysctl) but whose
/// other counters are fine — the shape that must degrade to an absent level, not a default one.
private final class PressurelessSource: SystemMetricSampling, @unchecked Sendable {
    func cpuTicks() -> CPUTicksSample? { CPUTicksSample(busyTicks: 100, totalTicks: 400) }
    func memory() -> MemorySample? { MemorySample(usedBytes: 8, totalBytes: 16) }
    func memoryPressure() -> MemoryPressureLevel? { nil }
    func wifiLinkMbps() -> Double? { 866 }
    func wifiState() -> WiFiStateSample? { WiFiStateSample(power: .on, rssi: -59) }
    func battery() -> BatterySample? { nil }
    func displayCount() -> Int? { 1 }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func collect(_ json: String) {
        lock.lock(); events.append(json); lock.unlock()
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}


@Test("the publisher emits schema-valid system.status.changed events on its cadence")
func publisherEmitsOnCadence() async throws {
    let collector = EventCollector()
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 3 }
    await publisher.stop()

    #expect(collector.count >= 3)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .systemStatusChanged)
    #expect(event.eventID.hasPrefix("brevt_"))
    #expect(collector.all[0].contains("\"category\":\"system_metrics\""))
    // The second tick has deltas: cpu 25%, battery 76, display 2 all present.
    #expect(collector.all[1].contains("\"battery\""))
    #expect(collector.all[1].contains("\"sampledAt\""))
    #expect(collector.all[1].contains("\"charging\":false"))
    #expect(collector.all[1].contains("\"pluggedIn\":true"))
}

@Test("the memory channel carries the kernel's pressure level over the wire (NIC-158)")
func publisherEmitsMemoryPressure() async throws {
    let collector = EventCollector()
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    // The level rides the memory channel as the contract's string, next to the percentage.
    #expect(collector.all[0].contains("\"pressure\":\"normal\""))
    #expect(collector.all[0].contains("\"memory\""))
}

@Test("an unsamplable pressure level is omitted from the payload rather than defaulted")
func publisherOmitsUnsamplablePressure() async throws {
    let collector = EventCollector()
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: PressurelessSource()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    // Absent, not "normal": the dashboard must fall back to the percentage, not be told the
    // machine is fine on no evidence.
    #expect(!collector.all[0].contains("\"pressure\":\"normal\""))
    #expect(collector.all[0].contains("\"category\":\"system_metrics\""))
}

// MARK: - Smoothing (NIC-158)

/// Builds snapshots directly so the smoothing can be driven at exact timestamps, rather than
/// through the real sampling loop where the cadence is wall-clock and the values are whatever the
/// machine happens to be doing.
private func cpuSnapshot(_ percent: Double?, at sampledAt: Date?, availability: MetricAvailability = .available) -> SystemStatusSnapshot {
    SystemStatusSnapshot(
        cpu: SystemStatusChannel(availability: availability, value: percent, sampledAt: sampledAt),
        memory: SystemStatusMemoryChannel(availability: .available, value: 50, pressure: .normal, sampledAt: sampledAt),
        network: SystemStatusNetworkChannel(availability: .unavailable, linkMbps: nil, power: .absent, signalRssi: nil, sampledAt: nil),
        battery: SystemStatusBatteryChannel(availability: .unavailable, percent: nil, isCharging: nil, isPluggedIn: nil, sampledAt: nil),
        display: SystemStatusChannel(availability: .available, value: 1, sampledAt: sampledAt)
    )
}

private let smoothingStart = Date(timeIntervalSince1970: 1_780_000_000)

@Test("the streamed CPU value is time-averaged, so a spike cannot colour the bar (NIC-158)")
func streamedCpuIsSmoothed() async throws {
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()), emit: { _ in }
    )

    // The first reading is adopted verbatim — no ramp from zero.
    let first = await publisher.smoothed(cpuSnapshot(10, at: smoothingStart))
    #expect(first.cpu.value == 10)

    // One 2 s tick at 100% barely moves it, and certainly does not reach the panel's yellow (60).
    let spiked = await publisher.smoothed(cpuSnapshot(100, at: smoothingStart.addingTimeInterval(2)))
    let spikedValue = try #require(spiked.cpu.value)
    #expect(spikedValue < 20)

    // Sustained load does climb: a minute of pegging clears the red threshold (85).
    var now = smoothingStart.addingTimeInterval(2)
    var latest = spikedValue
    for _ in 0..<30 {
        now = now.addingTimeInterval(2)
        latest = try #require(await publisher.smoothed(cpuSnapshot(100, at: now)).cpu.value)
    }
    #expect(latest > 85, "sustained load must reach red")
}

@Test("smoothing replaces only the value — availability, timestamp, and pressure pass through")
func smoothingPreservesEverythingElse() async throws {
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()), emit: { _ in }
    )
    let snapshot = cpuSnapshot(10, at: smoothingStart)
    let smoothed = await publisher.smoothed(snapshot)

    #expect(smoothed.cpu.availability == snapshot.cpu.availability)
    #expect(smoothed.cpu.sampledAt == snapshot.cpu.sampledAt)
    #expect(smoothed.memory.pressure == .normal)
    #expect(smoothed.memory.availability == .available)
    // Point-in-time channels are untouched — there is nothing to average about them.
    #expect(smoothed.network == snapshot.network)
    #expect(smoothed.battery == snapshot.battery)
    #expect(smoothed.display == snapshot.display)
}

@Test("an unavailable or loading channel resets the average rather than coasting on it")
func unusableSampleResetsTheAverage() async throws {
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()), emit: { _ in }
    )

    // Build up a high average.
    var now = smoothingStart
    for _ in 0..<60 {
        now = now.addingTimeInterval(2)
        _ = await publisher.smoothed(cpuSnapshot(95, at: now))
    }
    #expect(try #require(await publisher.smoothed(cpuSnapshot(95, at: now.addingTimeInterval(2))).cpu.value) > 80)

    // CPU sampling fails: the channel passes through untouched, carrying no value.
    let broken = await publisher.smoothed(cpuSnapshot(nil, at: nil, availability: .unavailable))
    #expect(broken.cpu.value == nil)

    // On recovery the reading is adopted whole — NOT blended back into the stale 95% curve, which
    // would show a machine at 90% for a minute after it went idle.
    let recovered = await publisher.smoothed(cpuSnapshot(5, at: now.addingTimeInterval(120)))
    #expect(recovered.cpu.value == 5)
}

@Test("pausing drops the history so the resume tick re-seeds from a real reading")
func pauseResetsTheAverage() async throws {
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()), emit: { _ in }
    )
    var now = smoothingStart
    for _ in 0..<60 {
        now = now.addingTimeInterval(2)
        _ = await publisher.smoothed(cpuSnapshot(95, at: now))
    }

    // Nothing is sampled while the dashboard is hidden, so there is no history to continue.
    await publisher.setActive(false)

    let afterResume = await publisher.smoothed(cpuSnapshot(12, at: now.addingTimeInterval(300)))
    #expect(afterResume.cpu.value == 12, "the first reading after a pause must not be blended with pre-pause load")
}

@Test("a paused publisher emits nothing; resuming emits immediately")
func pauseStopsEmissionAndResumeIsImmediate() async throws {
    let collector = EventCollector()
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 2 }

    await publisher.setActive(false)
    // Allow any in-flight tick to land, then verify silence over several intervals.
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    // Resume emits a fresh snapshot immediately, not after the next interval.
    await publisher.setActive(true)
    await waitUntil { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}

@Test("the payload carries the Wi-Fi link rate with a timestamp")
func payloadCarriesLinkRate() async throws {
    let status = MacSystemStatusCapability(source: SteadySource())
    _ = await status.snapshot() // prime the CPU delta
    let snapshot = await status.snapshot()

    #expect(snapshot.network.availability == .available)
    let link = try #require(snapshot.network.linkMbps)
    #expect(link == 866)
    #expect(snapshot.network.sampledAt != nil)
    #expect(snapshot.cpu.value == 25.0)

    // And the same snapshot maps into the event payload shape verbatim.
    let payload = SystemStatusPublisher.payload(snapshot)
    #expect(payload.network.linkMbps == link)
    #expect(payload.network.unit == "mbps")
    #expect(payload.cpu.availability == "available")

    // The radio's state rides the same channel as a wire-level string (NIC-156).
    #expect(payload.network.wifiPower == "on")
    #expect(payload.network.signalRssi == -59)
}
#endif
