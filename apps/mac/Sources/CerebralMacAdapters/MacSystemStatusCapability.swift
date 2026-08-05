// Live system status adapter (NIC-81, MAC-ADAPTER-3).
#if canImport(AppKit)
import Darwin
import Foundation
import IOKit.ps
import CoreGraphics
import CoreWLAN
import CerebralTools

/// One raw sample of the machine's counters, produced by ``SystemMetricSampling``.
/// CPU and network are *cumulative* counters — throughput and load are computed
/// as deltas between consecutive samples by the adapter, never by the source.
public struct CPUTicksSample: Equatable, Sendable {
    public let busyTicks: Double
    public let totalTicks: Double

    public init(busyTicks: Double, totalTicks: Double) {
        self.busyTicks = busyTicks
        self.totalTicks = totalTicks
    }
}

public struct MemorySample: Equatable, Sendable {
    public let usedBytes: Double
    public let totalBytes: Double

    public init(usedBytes: Double, totalBytes: Double) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

/// macOS's own memory-pressure level (NIC-158) — the kernel's verdict on whether memory is
/// actually under strain, which the used/total ratio cannot tell you: the OS deliberately keeps
/// RAM full of cache, so `memoryPercent` sits near 100% on a healthy machine.
///
/// These are the three levels the public `DispatchSource` memory-pressure API reports, read here
/// through the sysctl that backs it so the poll-shaped ``SystemMetricSampling`` seam can carry it.
public enum MemoryPressureLevel: String, Equatable, Sendable {
    case normal
    case warn
    case critical
}

/// The battery's charge level and power state (IOKit power sources).
/// `isCharging` means actively taking charge; `isPluggedIn` means on external
/// power (a full battery on AC is plugged in but not charging).
public struct BatterySample: Equatable, Sendable {
    public let percent: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool

    public init(percent: Double, isCharging: Bool, isPluggedIn: Bool) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

/// The Wi-Fi radio's power state (NIC-156). `absent` means this machine has no
/// Wi-Fi interface at all; `off` means it has one the user switched off. Keeping
/// them distinct is what lets the bar indicator stop claiming "Wi-Fi connected"
/// on a desktop Mac wired to Ethernet.
public enum WiFiPower: String, Equatable, Sendable {
    case on
    case off
    case absent
}

/// One sample of the Wi-Fi radio: its power state, and the associated network's
/// signal strength in dBm when there is one. `rssi` is `nil` whenever the radio is
/// off, absent, or on but not associated — never a fabricated floor value.
public struct WiFiStateSample: Equatable, Sendable {
    public let power: WiFiPower
    public let rssi: Double?

    public init(power: WiFiPower, rssi: Double?) {
        self.power = power
        self.rssi = rssi
    }
}

/// The raw-counter seam over Mach / getifaddrs / IOKit / CoreGraphics, so the
/// delta math and availability mapping are unit-testable with scripted samples.
/// Any `nil` means "this metric cannot be sampled right now" and maps to an
/// honest `.unavailable` reading (FR-SHL-06) without affecting other metrics.
public protocol SystemMetricSampling: Sendable {
    func cpuTicks() -> CPUTicksSample?
    func memory() -> MemorySample?
    /// The kernel's current memory-pressure level (NIC-158). `nil` when it cannot be sampled or
    /// the kernel reports a value this OS version does not define — an honest absence the
    /// dashboard falls back from, never a guessed `normal` (which would claim the machine is fine
    /// on no evidence).
    func memoryPressure() -> MemoryPressureLevel?
    /// The Wi-Fi interface's current transmit (link) rate in Mbps — the negotiated
    /// PHY rate to the access point, not measured throughput (NIC-135). `nil` when
    /// there is no associated Wi-Fi interface (Ethernet, Wi-Fi off, sampling failed),
    /// which maps to an honest `.unavailable` reading.
    func wifiLinkMbps() -> Double?
    /// The Wi-Fi radio's power state and signal strength (NIC-156). `nil` means the
    /// Wi-Fi subsystem could not be sampled at all, which reports as `absent` rather
    /// than guessing. Independent of `wifiLinkMbps()`: a radio can be on with no
    /// association (no link rate) and must still read as `on`.
    func wifiState() -> WiFiStateSample?
    /// Battery charge and charging state, or `nil` when no internal battery
    /// exists (or sampling failed) — a desktop Mac honestly reports unavailable.
    func battery() -> BatterySample?
    func displayCount() -> Int?
}

/// One computed channel of the rich status snapshot the publisher streams to
/// the dashboard (NIC-81b). `sampledAt` is the wall-clock time of the sample
/// that produced the value, so stale data stays timestamped downstream.
public struct SystemStatusChannel: Equatable, Sendable {
    public let availability: MetricAvailability
    public let value: Double?
    public let sampledAt: Date?
}

/// Network reports the Wi-Fi link (transmit) rate — the connection's speed, not
/// current throughput (NIC-135). The portable tool reading exposes the same value.
///
/// `availability` and `linkMbps` describe the *link rate* metric only; `power` and
/// `signalRssi` (NIC-156) are independent facts about the radio itself, deliberately
/// not folded into `availability`. A machine on Ethernet has no link rate
/// (`.unavailable`) while its Wi-Fi radio may still be legitimately `on`, and the
/// bar indicator needs that distinction to tell the truth.
public struct SystemStatusNetworkChannel: Equatable, Sendable {
    public let availability: MetricAvailability
    public let linkMbps: Double?
    public let power: WiFiPower
    public let signalRssi: Double?
    public let sampledAt: Date?
}

/// Memory carries both the used/total percentage and the kernel's pressure level (NIC-158).
///
/// They are deliberately independent facts, the same way the Wi-Fi radio's `power` is independent
/// of the link-rate `availability`. `availability`/`value` describe the *usage percentage* only;
/// `pressure` can be present when the percentage is unavailable, or absent when it is available
/// (a non-macOS host, or a level this OS version does not define). The dashboard renders the
/// percentage as the bar and takes the bar's colour from the pressure.
public struct SystemStatusMemoryChannel: Equatable, Sendable {
    public let availability: MetricAvailability
    public let value: Double?
    public let pressure: MemoryPressureLevel?
    public let sampledAt: Date?
}

/// Battery keeps its charging flag for the dashboard's bolt indicator; the
/// portable tool reading remains the charge percent.
public struct SystemStatusBatteryChannel: Equatable, Sendable {
    public let availability: MetricAvailability
    public let percent: Double?
    public let isCharging: Bool?
    public let isPluggedIn: Bool?
    public let sampledAt: Date?
}

/// A full rich reading of every metric, shared source of truth for the status
/// publisher. The one-shot `system.status.read` tool maps the same channels
/// onto the portable `SystemMetricReading` contract.
public struct SystemStatusSnapshot: Equatable, Sendable {
    public let cpu: SystemStatusChannel
    public let memory: SystemStatusMemoryChannel
    public let network: SystemStatusNetworkChannel
    public let battery: SystemStatusBatteryChannel
    public let display: SystemStatusChannel
}

/// The live system metrics adapter: CPU and memory from Mach host statistics,
/// network link rate from CoreWLAN, battery from IOKit power sources, displays
/// from CoreGraphics (PRD §5.2, TECH-STACK "Native Platform Adapters").
///
/// An actor because CPU is a rate metric that needs the previous sample: the
/// first CPU read honestly reports `.loading` (there is no delta yet) rather than
/// fabricating a since-boot average. Network is now the Wi-Fi link rate — an
/// instantaneous reading with no delta (NIC-135). The composition binds ONE
/// instance, so the one-shot `system.status.read` tool and the streaming status
/// publisher (NIC-81b) share the same CPU delta state.
public actor MacSystemStatusCapability: SystemStatusCapability {
    private let source: any SystemMetricSampling
    private let wallClock: @Sendable () -> Date

    private var previousCPU: CPUTicksSample?
    private var lastCPUPercent: Double?

    public init(
        source: any SystemMetricSampling = LiveSystemMetricSource(),
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.wallClock = wallClock
    }

    // MARK: - Portable tool contract

    public func readMetrics(_ ids: [SystemMetricID]) async throws -> [SystemMetricReading] {
        let requested = ids.isEmpty ? SystemMetricID.allCases : ids
        return requested.map { id in
            switch id {
            case .cpu:
                return reading(.cpu, cpuChannel(), unit: "percent")
            case .memory:
                // The portable tool reading stays the usage percentage — pressure is a richer
                // channel the streaming snapshot carries, not part of the portable contract.
                let channel = memoryChannel()
                return SystemMetricReading(id: .memory, availability: channel.availability, value: channel.value, unit: "percent")
            case .network:
                let channel = networkChannel()
                return SystemMetricReading(id: .network, availability: channel.availability, value: channel.linkMbps, unit: "mbps")
            case .battery:
                let channel = batteryChannel()
                return SystemMetricReading(id: .battery, availability: channel.availability, value: channel.percent, unit: "percent")
            case .display:
                return reading(.display, displayChannel(), unit: nil)
            }
        }
    }

    /// The rich per-channel snapshot the status publisher streams (NIC-81b).
    /// Shares the same delta state as `readMetrics`.
    public func snapshot() -> SystemStatusSnapshot {
        SystemStatusSnapshot(
            cpu: cpuChannel(),
            memory: memoryChannel(),
            network: networkChannel(),
            battery: batteryChannel(),
            display: displayChannel()
        )
    }

    private func reading(_ id: SystemMetricID, _ channel: SystemStatusChannel, unit: String?) -> SystemMetricReading {
        SystemMetricReading(id: id, availability: channel.availability, value: channel.value, unit: unit)
    }

    // MARK: - Per-metric channels

    private func cpuChannel() -> SystemStatusChannel {
        guard let sample = source.cpuTicks() else {
            return SystemStatusChannel(availability: .unavailable, value: nil, sampledAt: nil)
        }
        let sampledAt = wallClock()
        defer { previousCPU = sample }
        guard let previous = previousCPU else {
            return SystemStatusChannel(availability: .loading, value: nil, sampledAt: sampledAt)
        }
        let totalDelta = sample.totalTicks - previous.totalTicks
        guard totalDelta > 0 else {
            // Re-sampled within the same tick: reuse the last computed load
            // rather than dividing by zero or flapping back to loading.
            guard let last = lastCPUPercent else {
                return SystemStatusChannel(availability: .loading, value: nil, sampledAt: sampledAt)
            }
            return SystemStatusChannel(availability: .available, value: last, sampledAt: sampledAt)
        }
        let busyDelta = sample.busyTicks - previous.busyTicks
        let percent = max(0, min(1, busyDelta / totalDelta)) * 100
        lastCPUPercent = percent
        return SystemStatusChannel(availability: .available, value: percent, sampledAt: sampledAt)
    }

    private func memoryChannel() -> SystemStatusMemoryChannel {
        // Sampled independently of the usage percentage (NIC-158): a machine whose vm statistics
        // cannot be read may still report a pressure level, and vice versa. Neither absence is
        // allowed to suppress the other.
        let pressure = source.memoryPressure()
        guard let sample = source.memory(), sample.totalBytes > 0 else {
            return SystemStatusMemoryChannel(
                availability: .unavailable, value: nil, pressure: pressure, sampledAt: nil
            )
        }
        let percent = max(0, min(1, sample.usedBytes / sample.totalBytes)) * 100
        return SystemStatusMemoryChannel(
            availability: .available, value: percent, pressure: pressure, sampledAt: wallClock()
        )
    }

    private func networkChannel() -> SystemStatusNetworkChannel {
        // The radio's power state is sampled independently of the link rate: an
        // unsamplable Wi-Fi subsystem reports `absent` rather than guessing `off`
        // (NIC-156). Signal strength is only meaningful while the radio is on.
        let wifi = source.wifiState()
        let power = wifi?.power ?? .absent
        let signalRssi = power == .on ? wifi?.rssi : nil

        // The Wi-Fi link rate is an instantaneous CoreWLAN reading — no delta, so
        // it is `.available` on the first sample. A non-positive or missing rate
        // means no associated Wi-Fi interface (Ethernet, Wi-Fi off), reported as
        // an honest `.unavailable` (NIC-135).
        guard let linkMbps = source.wifiLinkMbps(), linkMbps > 0 else {
            return SystemStatusNetworkChannel(
                availability: .unavailable,
                linkMbps: nil,
                power: power,
                signalRssi: signalRssi,
                sampledAt: nil
            )
        }
        return SystemStatusNetworkChannel(
            availability: .available,
            linkMbps: linkMbps,
            power: power,
            signalRssi: signalRssi,
            sampledAt: wallClock()
        )
    }

    private func batteryChannel() -> SystemStatusBatteryChannel {
        guard let sample = source.battery() else {
            return SystemStatusBatteryChannel(availability: .unavailable, percent: nil, isCharging: nil, isPluggedIn: nil, sampledAt: nil)
        }
        return SystemStatusBatteryChannel(
            availability: .available,
            percent: max(0, min(100, sample.percent)),
            isCharging: sample.isCharging,
            isPluggedIn: sample.isPluggedIn,
            sampledAt: wallClock()
        )
    }

    private func displayChannel() -> SystemStatusChannel {
        guard let count = source.displayCount() else {
            return SystemStatusChannel(availability: .unavailable, value: nil, sampledAt: nil)
        }
        return SystemStatusChannel(availability: .available, value: Double(count), sampledAt: wallClock())
    }
}

// MARK: - Live source

/// The real counters: Mach host statistics (CPU/memory), CoreWLAN transmit rate
/// (network link speed), IOKit power sources (battery), and CoreGraphics active
/// displays (thread-safe, unlike NSScreen).
public struct LiveSystemMetricSource: SystemMetricSampling {
    public init() {}

    public func cpuTicks() -> CPUTicksSample? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        return CPUTicksSample(busyTicks: busy, totalTicks: busy + idle)
    }

    public func memory() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0) == 0, totalBytes > 0 else { return nil }
        let pageSize = Double(getpagesize())
        // Matches Activity Monitor's "Memory Used": app (anonymous) memory minus
        // purgeable, plus wired and compressed — so the panel agrees with what
        // the user cross-checks against.
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count)
            + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return MemorySample(usedBytes: max(0, used), totalBytes: Double(totalBytes))
    }

    public func memoryPressure() -> MemoryPressureLevel? {
        // `kern.memorystatus_vm_pressure_level` is the sysctl behind the public
        // DISPATCH_SOURCE_TYPE_MEMORYPRESSURE levels, and the only poll-shaped way to read them —
        // the dispatch source is edge-triggered, which does not fit this sampling seam.
        //
        // It is not a documented API surface, so an unrecognized value is reported as `nil` rather
        // than coerced to the nearest level: a future OS adding a state must degrade to "we don't
        // know" (the dashboard then falls back to the usage percentage), never to a confident
        // "normal" that would claim the machine is fine on no evidence.
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        switch level {
        case 1: return .normal
        case 2: return .warn
        case 4: return .critical
        default: return nil
        }
    }

    public func wifiLinkMbps() -> Double? {
        // CoreWLAN's default interface transmit rate is the negotiated PHY link
        // rate in Mbps. It reads without Location authorization (unlike ssid/bssid).
        // No Wi-Fi interface, or a non-positive rate, means "not on Wi-Fi".
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let rate = interface.transmitRate()
        return rate > 0 ? rate : nil
    }

    public func wifiState() -> WiFiStateSample? {
        // `powerOn()` and `rssiValue()` read without Location authorization — unlike
        // `ssid()`/`bssid()`, which return nil unless the app is authorized (macOS 14+).
        // That is why the indicator reports state and signal but not a network name.
        guard let interface = CWWiFiClient.shared().interface() else {
            return WiFiStateSample(power: .absent, rssi: nil)
        }
        guard interface.powerOn() else {
            return WiFiStateSample(power: .off, rssi: nil)
        }
        // CoreWLAN reports 0 dBm for "on but not associated" — a real reading of 0
        // is not physically meaningful here, so treat it as no signal rather than a
        // perfect one.
        let rssi = interface.rssiValue()
        return WiFiStateSample(power: .on, rssi: rssi == 0 ? nil : Double(rssi))
    }

    public func battery() -> BatterySample? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for powerSource in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, powerSource)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return BatterySample(
                percent: Double(current) / Double(maximum) * 100,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn
            )
        }
        return nil
    }

    public func displayCount() -> Int? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return nil }
        return Int(count)
    }
}
#endif
