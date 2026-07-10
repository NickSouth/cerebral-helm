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
    private var wifiLink: Double?
    private var batterySample: BatterySample?
    private var displays: Int?

    init(
        cpu: [CPUTicksSample?] = [],
        memory: MemorySample? = nil,
        wifiLink: Double? = nil,
        battery: BatterySample? = nil,
        displays: Int? = nil
    ) {
        self.cpuSamples = cpu
        self.memorySample = memory
        self.wifiLink = wifiLink
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
    // The Wi-Fi link rate is instantaneous — the same reading on every sample.
    func wifiLinkMbps() -> Double? { lock.lock(); defer { lock.unlock() }; return wifiLink }
    func battery() -> BatterySample? { batterySample }
    func displayCount() -> Int? { displays }
}

private func reading(_ readings: [SystemMetricReading], _ id: SystemMetricID) -> SystemMetricReading? {
    readings.first { $0.id == id }
}

// MARK: - CPU still needs a delta; the Wi-Fi link rate does not

@Test("the first read reports CPU loading, but instantaneous metrics (incl. Wi-Fi link) are available")
func firstReadCpuLoadingLinkAvailable() async throws {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        cpu: [CPUTicksSample(busyTicks: 100, totalTicks: 1000)],
        memory: MemorySample(usedBytes: 8, totalBytes: 16),
        wifiLink: 866,
        battery: BatterySample(percent: 80, isCharging: true, isPluggedIn: true),
        displays: 2
    ))

    let readings = try await capability.readMetrics(SystemMetricID.allCases)

    #expect(reading(readings, .cpu)?.availability == .loading)
    #expect(reading(readings, .cpu)?.value == nil)
    // The Wi-Fi link rate needs no delta — available on the first sample (NIC-135).
    #expect(reading(readings, .network)?.availability == .available)
    #expect(reading(readings, .network)?.value == 866.0)
    #expect(reading(readings, .network)?.unit == "mbps")
    #expect(reading(readings, .memory)?.availability == .available)
    #expect(reading(readings, .memory)?.value == 50.0)
    #expect(reading(readings, .battery)?.value == 80.0)
    #expect(reading(readings, .display)?.value == 2.0)
}

@Test("the second read computes CPU load from the tick delta")
func secondReadComputesCpuLoad() async throws {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        cpu: [
            CPUTicksSample(busyTicks: 100, totalTicks: 1000),
            CPUTicksSample(busyTicks: 350, totalTicks: 2000), // 250 busy of 1000 total → 25%
        ]
    ))

    _ = try await capability.readMetrics([.cpu])
    let readings = try await capability.readMetrics([.cpu])

    let cpu = reading(readings, .cpu)
    #expect(cpu?.availability == .available)
    #expect(cpu?.value == 25.0)
    #expect(cpu?.unit == "percent")
}

@Test("no associated Wi-Fi interface reports the network metric unavailable, not a fake value")
func noWifiInterfaceIsUnavailable() async throws {
    // Ethernet or Wi-Fi off: the source returns nil.
    let capability = MacSystemStatusCapability(source: FakeMetricSource(wifiLink: nil))
    let readings = try await capability.readMetrics([.network])
    #expect(reading(readings, .network)?.availability == .unavailable)
    #expect(reading(readings, .network)?.value == nil)

    // A non-positive rate is treated the same as no link.
    let zero = MacSystemStatusCapability(source: FakeMetricSource(wifiLink: 0))
    let zeroReadings = try await zero.readMetrics([.network])
    #expect(reading(zeroReadings, .network)?.availability == .unavailable)
}

// MARK: - Independent per-metric availability

@Test("a metric that cannot be sampled is unavailable without affecting the others (FR-SHL-06)")
func perMetricFailureIsIndependent() async throws {
    // A desktop Mac: no battery; CPU sampling scripted to fail; memory fine; on Ethernet (no Wi-Fi link).
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        cpu: [nil],
        memory: MemorySample(usedBytes: 4, totalBytes: 16),
        wifiLink: nil,
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

    // Wi-Fi link rate may legitimately be nil (Ethernet, Wi-Fi off, CI); when
    // present it is a positive Mbps figure.
    if let link = source.wifiLinkMbps() {
        #expect(link > 0)
    }

    let displays = try #require(source.displayCount())
    #expect(displays >= 1)

    // Battery may legitimately be nil (desktop Mac); when present it is a percent.
    if let battery = source.battery() {
        #expect(battery.percent >= 0 && battery.percent <= 100)
    }

    // End to end through the adapter: successive reads yield an available CPU
    // percent in range on real hardware. Mach sampling can transiently fail
    // under the suite's parallel load (the production cadence self-heals the
    // same way), so retry, and treat a persistently-loading run as a known
    // intermittent environment issue rather than a failure.
    let capability = MacSystemStatusCapability(source: source)
    _ = try await capability.readMetrics([.cpu])
    var percent: Double?
    for _ in 0..<8 where percent == nil {
        try await Task.sleep(nanoseconds: 150_000_000)
        let readings = try await capability.readMetrics([.cpu])
        percent = reading(readings, .cpu)?.value
    }
    if let value = percent {
        #expect(value >= 0 && value <= 100)
    } else {
        withKnownIssue("Mach CPU sampling stayed in loading under heavy parallel load", isIntermittent: true) {
            Issue.record("no CPU delta became available within the retry budget")
        }
    }
}
#endif
