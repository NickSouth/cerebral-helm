// Live system status adapter (NIC-81, MAC-ADAPTER-3).
#if canImport(AppKit)
import Darwin
import Foundation
import IOKit.ps
import CoreGraphics
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

/// Cumulative received/sent bytes across non-loopback interfaces since boot.
public struct NetworkBytesSample: Equatable, Sendable {
    public let inBytes: UInt64
    public let outBytes: UInt64

    public init(inBytes: UInt64, outBytes: UInt64) {
        self.inBytes = inBytes
        self.outBytes = outBytes
    }
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

/// The raw-counter seam over Mach / getifaddrs / IOKit / CoreGraphics, so the
/// delta math and availability mapping are unit-testable with scripted samples.
/// Any `nil` means "this metric cannot be sampled right now" and maps to an
/// honest `.unavailable` reading (FR-SHL-06) without affecting other metrics.
public protocol SystemMetricSampling: Sendable {
    func cpuTicks() -> CPUTicksSample?
    func memory() -> MemorySample?
    func networkBytes() -> NetworkBytesSample?
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

/// Network keeps its direction split for the dashboard's up/down display; the
/// portable tool reading remains the combined throughput.
public struct SystemStatusNetworkChannel: Equatable, Sendable {
    public let availability: MetricAvailability
    public let uploadMbps: Double?
    public let downloadMbps: Double?
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
    public let memory: SystemStatusChannel
    public let network: SystemStatusNetworkChannel
    public let battery: SystemStatusBatteryChannel
    public let display: SystemStatusChannel
}

/// The live system metrics adapter: CPU and memory from Mach host statistics,
/// network throughput from interface byte-counter deltas, battery from IOKit
/// power sources, displays from CoreGraphics (PRD §5.2, TECH-STACK "Native
/// Platform Adapters").
///
/// An actor because CPU and network are rate metrics that need the previous
/// sample: the first read of a rate metric honestly reports `.loading` (there is
/// no delta yet) rather than fabricating a since-boot average. The composition
/// binds ONE instance, so the one-shot `system.status.read` tool and the
/// streaming status publisher (NIC-81b) share the same delta state.
public actor MacSystemStatusCapability: SystemStatusCapability {
    private let source: any SystemMetricSampling
    private let nowNanos: @Sendable () -> UInt64
    private let wallClock: @Sendable () -> Date

    private var previousCPU: CPUTicksSample?
    private var lastCPUPercent: Double?
    private var previousNetwork: NetworkBytesSample?
    private var previousNetworkAtNanos: UInt64?
    private var lastNetworkMbps: (up: Double, down: Double)?

    public init(
        source: any SystemMetricSampling = LiveSystemMetricSource(),
        nowNanos: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.nowNanos = nowNanos
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
                return reading(.memory, memoryChannel(), unit: "percent")
            case .network:
                let channel = networkChannel()
                let combined = (channel.uploadMbps ?? 0) + (channel.downloadMbps ?? 0)
                let value: Double? = (channel.uploadMbps == nil && channel.downloadMbps == nil) ? nil : combined
                return SystemMetricReading(id: .network, availability: channel.availability, value: value, unit: "mbps")
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

    private func memoryChannel() -> SystemStatusChannel {
        guard let sample = source.memory(), sample.totalBytes > 0 else {
            return SystemStatusChannel(availability: .unavailable, value: nil, sampledAt: nil)
        }
        let percent = max(0, min(1, sample.usedBytes / sample.totalBytes)) * 100
        return SystemStatusChannel(availability: .available, value: percent, sampledAt: wallClock())
    }

    private func networkChannel() -> SystemStatusNetworkChannel {
        guard let sample = source.networkBytes() else {
            return SystemStatusNetworkChannel(availability: .unavailable, uploadMbps: nil, downloadMbps: nil, sampledAt: nil)
        }
        let now = nowNanos()
        let sampledAt = wallClock()
        defer {
            previousNetwork = sample
            previousNetworkAtNanos = now
        }
        guard let previous = previousNetwork, let previousAt = previousNetworkAtNanos else {
            return SystemStatusNetworkChannel(availability: .loading, uploadMbps: nil, downloadMbps: nil, sampledAt: sampledAt)
        }
        let elapsedSeconds = Double(now &- previousAt) / 1_000_000_000
        // A shrunken counter means an underlying 32-bit interface counter
        // wrapped (or an interface vanished): the delta is meaningless once, so
        // reuse the last known rate instead of reporting garbage.
        guard elapsedSeconds > 0, sample.inBytes >= previous.inBytes, sample.outBytes >= previous.outBytes else {
            guard let last = lastNetworkMbps else {
                return SystemStatusNetworkChannel(availability: .loading, uploadMbps: nil, downloadMbps: nil, sampledAt: sampledAt)
            }
            return SystemStatusNetworkChannel(availability: .available, uploadMbps: last.up, downloadMbps: last.down, sampledAt: sampledAt)
        }
        let downMbps = Double(sample.inBytes - previous.inBytes) * 8 / elapsedSeconds / 1_000_000
        let upMbps = Double(sample.outBytes - previous.outBytes) * 8 / elapsedSeconds / 1_000_000
        lastNetworkMbps = (up: upMbps, down: downMbps)
        return SystemStatusNetworkChannel(availability: .available, uploadMbps: upMbps, downloadMbps: downMbps, sampledAt: sampledAt)
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

/// The real counters: Mach host statistics (CPU/memory), getifaddrs interface
/// byte counters (network), IOKit power sources (battery), and CoreGraphics
/// active displays (thread-safe, unlike NSScreen).
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

    public func networkBytes() -> NetworkBytesSample? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var inTotal: UInt64 = 0
        var outTotal: UInt64 = 0
        var cursor = addresses
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            inTotal &+= UInt64(data.ifi_ibytes)
            outTotal &+= UInt64(data.ifi_obytes)
        }
        return NetworkBytesSample(inBytes: inTotal, outBytes: outTotal)
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
