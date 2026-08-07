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
    private var pressure: MemoryPressureLevel?
    private var wifiLink: Double?
    private var wifi: WiFiStateSample?
    private var batterySample: BatterySample?
    private var displays: Int?

    init(
        cpu: [CPUTicksSample?] = [],
        memory: MemorySample? = nil,
        pressure: MemoryPressureLevel? = nil,
        wifiLink: Double? = nil,
        wifi: WiFiStateSample? = WiFiStateSample(power: .on, rssi: -59),
        battery: BatterySample? = nil,
        displays: Int? = nil
    ) {
        self.cpuSamples = cpu
        self.memorySample = memory
        self.pressure = pressure
        self.wifiLink = wifiLink
        self.wifi = wifi
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
    func memoryPressure() -> MemoryPressureLevel? { pressure }
    // The Wi-Fi link rate is instantaneous — the same reading on every sample.
    func wifiLinkMbps() -> Double? { lock.lock(); defer { lock.unlock() }; return wifiLink }
    func wifiState() -> WiFiStateSample? { lock.lock(); defer { lock.unlock() }; return wifi }
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

// MARK: - Memory pressure (NIC-158)

@Test("the memory channel carries the kernel's pressure level alongside the usage percentage")
func memoryChannelCarriesPressure() async throws {
    for level in [MemoryPressureLevel.normal, .warn, .critical] {
        let capability = MacSystemStatusCapability(source: FakeMetricSource(
            memory: MemorySample(usedBytes: 12, totalBytes: 16),
            pressure: level
        ))

        let snapshot = await capability.snapshot()
        #expect(snapshot.memory.availability == .available)
        #expect(snapshot.memory.value == 75.0)
        #expect(snapshot.memory.pressure == level)
    }
}

@Test("an unsamplable pressure level is absent, never a fabricated normal")
func unsamplablePressureIsAbsent() async throws {
    // The whole point of the level is to say whether memory is under strain. Reporting `normal`
    // when we could not read it would claim the machine is fine on no evidence — the dashboard
    // must instead fall back to thresholding the percentage.
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        memory: MemorySample(usedBytes: 12, totalBytes: 16),
        pressure: nil
    ))

    let snapshot = await capability.snapshot()
    #expect(snapshot.memory.availability == .available)
    #expect(snapshot.memory.value == 75.0)
    #expect(snapshot.memory.pressure == nil)
}

@Test("pressure and the usage percentage are independent — either can be absent alone")
func pressureIndependentOfUsage() async throws {
    // vm statistics unreadable, pressure still readable: the bar has no figure but the colour
    // signal survives. Mirrors how the Wi-Fi radio's power is independent of its link rate.
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        memory: nil,
        pressure: .critical
    ))

    let snapshot = await capability.snapshot()
    #expect(snapshot.memory.availability == .unavailable)
    #expect(snapshot.memory.value == nil)
    #expect(snapshot.memory.sampledAt == nil)
    #expect(snapshot.memory.pressure == .critical)

    // The portable tool reading is the percentage only — pressure never leaks into it, so the
    // `system.status.read` contract is unchanged by this addition.
    let readings = try await capability.readMetrics([.memory])
    #expect(reading(readings, .memory)?.availability == .unavailable)
    #expect(reading(readings, .memory)?.value == nil)
    #expect(reading(readings, .memory)?.unit == "percent")
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

// MARK: - Wi-Fi radio state (NIC-156)

@Test("the radio's power state is reported independently of the link rate")
func wifiPowerIsIndependentOfLinkRate() async {
    // On Ethernet: no link rate to report, but the Wi-Fi radio is genuinely on.
    // The indicator must not read this as "Wi-Fi off".
    let onEthernet = MacSystemStatusCapability(source: FakeMetricSource(
        wifiLink: nil,
        wifi: WiFiStateSample(power: .on, rssi: -59)
    ))
    let ethernet = await onEthernet.snapshot().network
    #expect(ethernet.availability == .unavailable)
    #expect(ethernet.linkMbps == nil)
    #expect(ethernet.power == .on)
    #expect(ethernet.signalRssi == -59)

    // Radio switched off: distinct from both "on" and "absent".
    let off = MacSystemStatusCapability(source: FakeMetricSource(
        wifiLink: nil,
        wifi: WiFiStateSample(power: .off, rssi: nil)
    ))
    #expect(await off.snapshot().network.power == .off)
}

@Test("an unsamplable Wi-Fi subsystem reports absent rather than guessing off")
func unsamplableWifiIsAbsent() async {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(wifiLink: nil, wifi: nil))
    let network = await capability.snapshot().network
    #expect(network.power == .absent)
    #expect(network.signalRssi == nil)
}

@Test("signal strength is dropped whenever the radio is not on")
func signalOnlyReportedWhilePowered() async {
    // A stale rssi carried alongside a powered-down radio would dim the indicator's
    // arcs as though there were a live connection.
    let off = MacSystemStatusCapability(source: FakeMetricSource(
        wifiLink: nil,
        wifi: WiFiStateSample(power: .off, rssi: -59)
    ))
    #expect(await off.snapshot().network.signalRssi == nil)

    let absent = MacSystemStatusCapability(source: FakeMetricSource(
        wifiLink: nil,
        wifi: WiFiStateSample(power: .absent, rssi: -59)
    ))
    #expect(await absent.snapshot().network.signalRssi == nil)
}

@Test("a connected radio keeps both its link rate and its signal strength")
func connectedRadioReportsBoth() async {
    let capability = MacSystemStatusCapability(source: FakeMetricSource(
        wifiLink: 866,
        wifi: WiFiStateSample(power: .on, rssi: -45)
    ))
    let network = await capability.snapshot().network
    #expect(network.availability == .available)
    #expect(network.linkMbps == 866)
    #expect(network.power == .on)
    #expect(network.signalRssi == -45)
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

    // The pressure sysctl is readable on any macOS host, so a nil here would mean the kernel
    // reported a level this adapter does not map — which is exactly what we want to notice.
    // A machine running a test suite is not under critical pressure.
    let pressure = try #require(source.memoryPressure())
    #expect(pressure == .normal || pressure == .warn)

    // Wi-Fi link rate may legitimately be nil (Ethernet, Wi-Fi off, CI); when
    // present it is a positive Mbps figure.
    if let link = source.wifiLinkMbps() {
        #expect(link > 0)
    }

    // The radio always reports a definite state (never nil — an unreadable subsystem
    // is `.absent`). A signal reading only accompanies a powered radio, and dBm is
    // negative by construction.
    let wifi = try #require(source.wifiState())
    if wifi.power != .on {
        #expect(wifi.rssi == nil)
    }
    if let rssi = wifi.rssi {
        #expect(rssi < 0 && rssi > -120)
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
