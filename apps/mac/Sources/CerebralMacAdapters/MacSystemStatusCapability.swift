// Live system status adapter (NIC-81a, MAC-ADAPTER-3).
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

/// The raw-counter seam over Mach / getifaddrs / IOKit / CoreGraphics, so the
/// delta math and availability mapping are unit-testable with scripted samples.
/// Any `nil` means "this metric cannot be sampled right now" and maps to an
/// honest `.unavailable` reading (FR-SHL-06) without affecting other metrics.
public protocol SystemMetricSampling: Sendable {
    func cpuTicks() -> CPUTicksSample?
    func memory() -> MemorySample?
    /// Cumulative bytes (in + out) across non-loopback interfaces since boot.
    func networkBytes() -> UInt64?
    /// Battery charge percent, or `nil` when no internal battery exists (or
    /// sampling failed) — a desktop Mac honestly reports unavailable.
    func batteryPercent() -> Double?
    func displayCount() -> Int?
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

    private var previousCPU: CPUTicksSample?
    private var lastCPUPercent: Double?
    private var previousNetworkBytes: UInt64?
    private var previousNetworkAtNanos: UInt64?
    private var lastNetworkMbps: Double?

    public init(
        source: any SystemMetricSampling = LiveSystemMetricSource(),
        nowNanos: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.source = source
        self.nowNanos = nowNanos
    }

    public func readMetrics(_ ids: [SystemMetricID]) async throws -> [SystemMetricReading] {
        let requested = ids.isEmpty ? SystemMetricID.allCases : ids
        return requested.map { id in
            switch id {
            case .cpu: return cpuReading()
            case .memory: return memoryReading()
            case .network: return networkReading()
            case .battery: return batteryReading()
            case .display: return displayReading()
            }
        }
    }

    // MARK: - Per-metric readings

    private func cpuReading() -> SystemMetricReading {
        guard let sample = source.cpuTicks() else {
            return SystemMetricReading(id: .cpu, availability: .unavailable, value: nil, unit: "percent")
        }
        defer { previousCPU = sample }
        guard let previous = previousCPU else {
            return SystemMetricReading(id: .cpu, availability: .loading, value: nil, unit: "percent")
        }
        let totalDelta = sample.totalTicks - previous.totalTicks
        guard totalDelta > 0 else {
            // Re-sampled within the same tick: reuse the last computed load
            // rather than dividing by zero or flapping back to loading.
            guard let last = lastCPUPercent else {
                return SystemMetricReading(id: .cpu, availability: .loading, value: nil, unit: "percent")
            }
            return SystemMetricReading(id: .cpu, availability: .available, value: last, unit: "percent")
        }
        let busyDelta = sample.busyTicks - previous.busyTicks
        let percent = (max(0, min(1, busyDelta / totalDelta))) * 100
        lastCPUPercent = percent
        return SystemMetricReading(id: .cpu, availability: .available, value: percent, unit: "percent")
    }

    private func memoryReading() -> SystemMetricReading {
        guard let sample = source.memory(), sample.totalBytes > 0 else {
            return SystemMetricReading(id: .memory, availability: .unavailable, value: nil, unit: "percent")
        }
        let percent = max(0, min(1, sample.usedBytes / sample.totalBytes)) * 100
        return SystemMetricReading(id: .memory, availability: .available, value: percent, unit: "percent")
    }

    private func networkReading() -> SystemMetricReading {
        guard let bytes = source.networkBytes() else {
            return SystemMetricReading(id: .network, availability: .unavailable, value: nil, unit: "mbps")
        }
        let now = nowNanos()
        defer {
            previousNetworkBytes = bytes
            previousNetworkAtNanos = now
        }
        guard let previousBytes = previousNetworkBytes, let previousAt = previousNetworkAtNanos else {
            return SystemMetricReading(id: .network, availability: .loading, value: nil, unit: "mbps")
        }
        let elapsedSeconds = Double(now &- previousAt) / 1_000_000_000
        // A shrunken counter means an underlying 32-bit interface counter
        // wrapped (or an interface vanished): the delta is meaningless once, so
        // reuse the last known rate instead of reporting garbage.
        guard elapsedSeconds > 0, bytes >= previousBytes else {
            guard let last = lastNetworkMbps else {
                return SystemMetricReading(id: .network, availability: .loading, value: nil, unit: "mbps")
            }
            return SystemMetricReading(id: .network, availability: .available, value: last, unit: "mbps")
        }
        let mbps = Double(bytes - previousBytes) * 8 / elapsedSeconds / 1_000_000
        lastNetworkMbps = mbps
        return SystemMetricReading(id: .network, availability: .available, value: mbps, unit: "mbps")
    }

    private func batteryReading() -> SystemMetricReading {
        guard let percent = source.batteryPercent() else {
            return SystemMetricReading(id: .battery, availability: .unavailable, value: nil, unit: "percent")
        }
        return SystemMetricReading(id: .battery, availability: .available, value: max(0, min(100, percent)), unit: "percent")
    }

    private func displayReading() -> SystemMetricReading {
        guard let count = source.displayCount() else {
            return SystemMetricReading(id: .display, availability: .unavailable, value: nil, unit: nil)
        }
        return SystemMetricReading(id: .display, availability: .available, value: Double(count), unit: nil)
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
        // "Used" approximates what Activity Monitor calls memory pressure input:
        // active + wired + compressed pages.
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return MemorySample(usedBytes: used, totalBytes: Double(totalBytes))
    }

    public func networkBytes() -> UInt64? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var total: UInt64 = 0
        var cursor = addresses
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            total &+= UInt64(data.ifi_ibytes) &+ UInt64(data.ifi_obytes)
        }
        return total
    }

    public func batteryPercent() -> Double? {
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
            return Double(current) / Double(maximum) * 100
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
