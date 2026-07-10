// On-demand internet capacity measurement (NIC-135).
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Measures internet capacity with Apple's `networkQuality`.
///
/// Runs one fixed invocation through the shared process capability — no shell, no
/// caller-supplied arguments — and parses the `-c` JSON capacity figures
/// (`dl_throughput`/`ul_throughput`, bits/s → Mbps). This is a read: it measures
/// and mutates nothing, so the tool is classified `read_only` (it is a specific
/// diagnostic, not arbitrary allowlisted shell like `hook.run`). `-M 30` bounds
/// the run; the default interface (the one carrying traffic) is used, not a
/// hardcoded `en0`.
public struct MacNetworkSpeedTestCapability: NetworkSpeedTestCapability {
    private let process: any ProcessCapability
    private let executable: String
    private let arguments: [String]

    public init(
        // networkQuality's JSON carries large diagnostic arrays; a generous output
        // cap keeps the payload intact so it stays parseable (a truncated JSON
        // blob would read as unavailable).
        process: any ProcessCapability = ProcessHookCapability(outputLimitBytes: 512 * 1024),
        executable: String = "/usr/bin/networkQuality",
        arguments: [String] = ["-c", "-M", "30"]
    ) {
        self.process = process
        self.executable = executable
        self.arguments = arguments
    }

    public func measure() async throws -> NetworkSpeedTestReading {
        let invocation = HookInvocation(
            executable: executable,
            arguments: arguments,
            workingDirectory: "/",
            environment: [:]
        )
        let result: ProcessRunResult
        do {
            result = try await process.run(invocation)
        } catch {
            throw NativeCapabilityError.adapterFailure("networkQuality could not be launched: \(error)")
        }
        if result.timedOut {
            throw NativeCapabilityError.timedOut
        }
        // A non-zero exit (no route to the test servers, etc.) is an honest
        // unavailable reading, never a fabricated figure.
        guard result.exitCode == 0 else {
            return NetworkSpeedTestReading(status: .unavailable, downloadMbps: nil, uploadMbps: nil)
        }
        return Self.parse(result.stdout)
    }

    /// Parses networkQuality's `-c` JSON. `dl_throughput`/`ul_throughput` are in
    /// bits per second; converted to Mbps (÷1e6 — decimal mega, matching the rest
    /// of the metrics). A missing direction degrades to `partial`/`unavailable`,
    /// never a guess.
    static func parse(_ stdout: String) -> NetworkSpeedTestReading {
        guard let data = stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return NetworkSpeedTestReading(status: .unavailable, downloadMbps: nil, uploadMbps: nil)
        }
        func mbps(_ key: String) -> Double? {
            guard let bitsPerSecond = (root[key] as? NSNumber)?.doubleValue, bitsPerSecond > 0 else { return nil }
            return bitsPerSecond / 1_000_000
        }
        let down = mbps("dl_throughput")
        let up = mbps("ul_throughput")
        switch (down, up) {
        case (.some, .some):
            return NetworkSpeedTestReading(status: .ok, downloadMbps: down, uploadMbps: up)
        case (nil, nil):
            return NetworkSpeedTestReading(status: .unavailable, downloadMbps: nil, uploadMbps: nil)
        default:
            return NetworkSpeedTestReading(status: .partial, downloadMbps: down, uploadMbps: up)
        }
    }
}
#endif
