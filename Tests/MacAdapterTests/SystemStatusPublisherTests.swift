// NIC-81b (MAC-ADAPTER-3): streaming system-status events.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralMacAdapters
import CerebralTools

/// A steady scripted source: constant counters advancing each call, so every
/// tick after the first produces available readings.
private final class SteadySource: SystemMetricSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: Double = 0
    private var bytes: UInt64 = 0

    func cpuTicks() -> CPUTicksSample? {
        lock.lock(); defer { lock.unlock() }
        ticks += 100
        return CPUTicksSample(busyTicks: ticks / 4, totalTicks: ticks)
    }

    func memory() -> MemorySample? { MemorySample(usedBytes: 8, totalBytes: 16) }

    func networkBytes() -> NetworkBytesSample? {
        lock.lock(); defer { lock.unlock() }
        bytes += 250_000
        return NetworkBytesSample(inBytes: bytes, outBytes: bytes / 2)
    }

    func battery() -> BatterySample? { BatterySample(percent: 76, isCharging: false, isPluggedIn: true) }
    func displayCount() -> Int? { 2 }
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

private func waitUntil(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
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
    await waitUntil(3000) { collector.count >= 3 }
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

@Test("a paused publisher emits nothing; resuming emits immediately")
func pauseStopsEmissionAndResumeIsImmediate() async throws {
    let collector = EventCollector()
    let publisher = SystemStatusPublisher(
        status: MacSystemStatusCapability(source: SteadySource()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 2 }

    await publisher.setActive(false)
    // Allow any in-flight tick to land, then verify silence over several intervals.
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    // Resume emits a fresh snapshot immediately, not after the next interval.
    await publisher.setActive(true)
    await waitUntil(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}

@Test("the payload carries the up/down network split with timestamps")
func payloadCarriesNetworkSplit() async throws {
    let status = MacSystemStatusCapability(source: SteadySource())
    _ = await status.snapshot() // prime the rate deltas
    try? await Task.sleep(nanoseconds: 20_000_000)
    let snapshot = await status.snapshot()

    #expect(snapshot.network.availability == .available)
    let up = try #require(snapshot.network.uploadMbps)
    let down = try #require(snapshot.network.downloadMbps)
    #expect(down > up, "the steady source downloads twice what it uploads")
    #expect(snapshot.network.sampledAt != nil)
    #expect(snapshot.cpu.value == 25.0)

    // And the same snapshot maps into the event payload shape verbatim.
    let payload = SystemStatusPublisher.payload(snapshot)
    #expect(payload.network.uploadMbps == up)
    #expect(payload.network.downloadMbps == down)
    #expect(payload.cpu.availability == "available")
}
#endif
