// NIC-81a (MAC-ADAPTER-3): native system metrics adapter.
//
// Delta math and availability mapping run against a scripted fake source; the
// live Mach/getifaddrs/IOKit/CoreGraphics source gets a real-hardware sanity
// check. Gated so the Linux CI package build compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralCore
import CerebralMacAdapters
import CerebralTools

/// A scripted source: each call pops the next sample. `nil` scripts a sampling
/// failure for that metric.
private final class FakeMetricSource: SystemMetricSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var cpuSamples: [CPUTicksSample?]
    private var memorySample: MemorySample?
    private var networkSamples: [NetworkBytesSample?]
    private var batterySample: BatterySample?
    private var displays: Int?

    init(
        cpu: [CPUTicksSample?] = [],
        memory: MemorySample? = nil,
        network: [NetworkBytesSample?] = [],
        battery: BatterySample? = nil,
        displays: Int? = nil
    ) {
        self.cpuSamples = cpu
        self.memorySample = memory
        self.networkSamples = network
        self.batterySample = battery
        self.displays = displays
    }

    private func pop<T>(_ samples: inout [T?]) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        return samples.removeFirst()
    }

    func cpuTicks() -> CPUTicksSample? { pop(&cpuSamples) }
    func memory() -> MemorySample? { memorySample }
    func networkBytes() -> NetworkBytesSample? { pop(&networkSamples) }
    func battery() -> BatterySample? { batterySample }
    func displayCount() -> Int? { displays }
}

/// A controllable monotonic clock for the network-rate denominator.
private final class FakeNow: @unchecked Sendable {
    private let lock = NSLock()
    private var nanos: UInt64 = 1_000_000_000

    func advance(seconds: Double) {
        lock.lock(); nanos += UInt64(seconds * 1_000_000_000); lock.unlock()
    }

    func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return nanos
    }
}

private func reading(_ readings: [SystemMetricReading], _ id: SystemMetricID) -> SystemMetricReading? {
    readings.first { $0.id == id }
}

// MARK: - Rate metrics need a delta

@Test("the first read of the rate metrics reports loading, never a fabricated value")
func firstRateReadIsLoading() async throws {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        cpu: [CPUTicksSample(busyTicks: 100, totalTicks: 1000)],
        memory: MemorySample(usedBytes: 8, totalBytes: 16),
        network: [NetworkBytesSample(inBytes: 1_000_000, outBytes: 0)],
        battery: BatterySample(percent: 80, isCharging: true, isPluggedIn: true),
        displays: 2
    ))

    let readings = try await capability.readMetrics(SystemMetricID.allCases)

    #expect(reading(readings, .cpu)?.availability == .loading)
    #expect(reading(readings, .cpu)?.value == nil)
    #expect(reading(readings, .network)?.availability == .loading)
    // Instantaneous metrics are available immediately.
    #expect(reading(readings, .memory)?.availability == .available)
    #expect(reading(readings, .memory)?.value == 50.0)
    #expect(reading(readings, .battery)?.value == 80.0)
    #expect(reading(readings, .display)?.value == 2.0)
}

@Test("the second read computes CPU load and network throughput from the deltas")
func secondReadComputesRates() async throws {
    let now = FakeNow()
    let capability = MacSystemStatusCapability(
        source: FakeMetricSource(
            cpu: [
                CPUTicksSample(busyTicks: 100, totalTicks: 1000),
                CPUTicksSample(busyTicks: 350, totalTicks: 2000), // 250 busy of 1000 total → 25%
            ],
            network: [
                NetworkBytesSample(inBytes: 1_000_000, outBytes: 500_000),
                NetworkBytesSample(inBytes: 3_000_000, outBytes: 1_000_000), // ↓2 MB + ↑0.5 MB in 2 s → 8 + 2 Mbit/s
            ]
        ),
        nowNanos: { now.now() }
    )

    _ = try await capability.readMetrics([.cpu, .network])
    now.advance(seconds: 2)
    let readings = try await capability.readMetrics([.cpu, .network])

    let cpu = reading(readings, .cpu)
    #expect(cpu?.availability == .available)
    #expect(cpu?.value == 25.0)
    #expect(cpu?.unit == "percent")

    let network = reading(readings, .network)
    #expect(network?.availability == .available)
    #expect(network?.value == 10.0)
    #expect(network?.unit == "mbps")
}

@Test("a wrapped network counter reuses the last known rate instead of reporting garbage")
func wrappedNetworkCounterReusesLastRate() async throws {
    let now = FakeNow()
    let capability = MacSystemStatusCapability(
        source: FakeMetricSource(network: [
            NetworkBytesSample(inBytes: 1_000_000, outBytes: 500_000),
            NetworkBytesSample(inBytes: 3_000_000, outBytes: 1_000_000),
            NetworkBytesSample(inBytes: 500, outBytes: 100), // shrank: wrap
        ]),
        nowNanos: { now.now() }
    )

    _ = try await capability.readMetrics([.network])
    now.advance(seconds: 2)
    _ = try await capability.readMetrics([.network]) // 10 mbps
    now.advance(seconds: 2)
    let readings = try await capability.readMetrics([.network])

    #expect(reading(readings, .network)?.availability == .available)
    #expect(reading(readings, .network)?.value == 10.0)
}

// MARK: - Independent per-metric availability

@Test("a metric that cannot be sampled is unavailable without affecting the others (FR-SHL-06)")
func perMetricFailureIsIndependent() async throws {
    // A desktop Mac: no battery; CPU sampling scripted to fail; memory fine.
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        cpu: [nil],
        memory: MemorySample(usedBytes: 4, totalBytes: 16),
        network: [],
        battery: nil,
        displays: 1
    ))

    let readings = try await capability.readMetrics(SystemMetricID.allCases)

    #expect(reading(readings, .cpu)?.availability == .unavailable)
    #expect(reading(readings, .battery)?.availability == .unavailable)
    #expect(reading(readings, .battery)?.value == nil)
    #expect(reading(readings, .network)?.availability == .unavailable)
    #expect(reading(readings, .memory)?.availability == .available)
    #expect(reading(readings, .memory)?.value == 25.0)
    #expect(reading(readings, .display)?.availability == .available)
}

@Test("an empty request returns every metric, in canonical order")
func emptyRequestReturnsAllMetrics() async throws {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(displays: 1))
    let readings = try await capability.readMetrics([])

    #expect(readings.map(\.id) == SystemMetricID.allCases)
}

// MARK: - Shared contract suite

@Test("the native status adapter satisfies the shared status contract case (FR-TOL-04)")
func nativeStatusAdapterSatisfiesContractCase() async {
    let bundle = ToolCapabilities(
        app: MockAppCapability(),
        url: MockURLCapability(),
        process: MockProcessCapability(),
        systemStatus: MacSystemStatusCapability(source: FakeMetricSource(
            cpu: [CPUTicksSample(busyTicks: 1, totalTicks: 10)],
            memory: MemorySample(usedBytes: 1, totalBytes: 2)
        )),
        nativeCapabilityIDs: [CapabilityMatrix.Capability.systemStatusRead]
    )
    let fixtures = AdapterContractFixtures(
        appID: "unused",
        urlID: "unused",
        hookID: "unused",
        hookInvocation: HookInvocation(executable: "/usr/bin/true", arguments: [], workingDirectory: "/", environment: [:]),
        searchQuery: "unused",
        metrics: [.cpu, .memory]
    )
    let cases = AdapterContractSuite.capabilityCases(bundle: bundle, fixtures: fixtures)
        .filter { $0.name.hasPrefix("system status") }
    #expect(cases.count == 1)
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}

// MARK: - Live source sanity (real hardware)

@Test("the live metric source returns plausible values on real hardware")
func liveSourceSanity() async throws {
    let source = LiveSystemMetricSource()

    let cpu = try #require(source.cpuTicks())
    #expect(cpu.totalTicks > 0)
    #expect(cpu.busyTicks >= 0 && cpu.busyTicks <= cpu.totalTicks)

    let memory = try #require(source.memory())
    #expect(memory.totalBytes > 0)
    #expect(memory.usedBytes > 0 && memory.usedBytes <= memory.totalBytes)

    let network = try #require(source.networkBytes())
    #expect(network.inBytes > 0)

    let displays = try #require(source.displayCount())
    #expect(displays >= 1)

    // Battery may legitimately be nil (desktop Mac); when present it is a percent.
    if let battery = source.battery() {
        #expect(battery.percent >= 0 && battery.percent <= 100)
    }

    // End to end through the adapter: successive reads yield an available CPU
    // percent in range on real hardware. A transient Mach sampling failure means
    // one more loading tick (the production cadence self-heals the same way), so
    // allow a few attempts rather than demanding exactly the second read.
    let capability = MacSystemStatusCapability(source: source)
    _ = try await capability.readMetrics([.cpu])
    var percent: Double?
    for _ in 0..<5 where percent == nil {
        try await Task.sleep(nanoseconds: 150_000_000)
        let readings = try await capability.readMetrics([.cpu])
        percent = reading(readings, .cpu)?.value
    }
    let value = try #require(percent)
    #expect(value >= 0 && value <= 100)
}
#endif
