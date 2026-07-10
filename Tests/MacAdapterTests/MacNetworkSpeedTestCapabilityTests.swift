// NIC-135: on-demand internet speed test adapter.
//
// The networkQuality JSON parsing and exit/timeout handling run against a stubbed
// process capability, so no real network test runs in CI. Gated so the Linux CI
// package build compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralTools
import CerebralMacAdapters

/// A scripted process: returns a canned result, or throws a scripted error.
private struct StubProcess: ProcessCapability {
    var result: ProcessRunResult
    var thrown: (any Error)?

    func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        if let thrown { throw thrown }
        return result
    }
}

private func processResult(exitCode: Int = 0, stdout: String = "", timedOut: Bool = false) -> ProcessRunResult {
    ProcessRunResult(
        exitCode: exitCode, stdout: stdout, stderr: "", environment: [:], timedOut: timedOut, durationMs: 120
    )
}

private func capability(_ result: ProcessRunResult, thrown: (any Error)? = nil) -> MacNetworkSpeedTestCapability {
    MacNetworkSpeedTestCapability(process: StubProcess(result: result, thrown: thrown))
}

@Test("both throughput figures parse to Mbps (bits/s ÷ 1e6) and report ok")
func bothDirectionsParseToMbps() async throws {
    // networkQuality -c fields are bits per second.
    let json = #"{ "dl_throughput": 100000000, "ul_throughput": 20000000, "interface_name": "en0" }"#
    let reading = try await capability(processResult(stdout: json)).measure()

    #expect(reading.status == .ok)
    #expect(reading.downloadMbps == 100)
    #expect(reading.uploadMbps == 20)
}

@Test("one measured direction reports partial with the other nil")
func oneDirectionIsPartial() async throws {
    let json = #"{ "dl_throughput": 55000000 }"#
    let reading = try await capability(processResult(stdout: json)).measure()

    #expect(reading.status == .partial)
    #expect(reading.downloadMbps == 55)
    #expect(reading.uploadMbps == nil)
}

@Test("no measured figures report unavailable, never a fabricated value")
func noFiguresIsUnavailable() async throws {
    let json = #"{ "interface_name": "en0", "base_rtt": 17.3 }"#
    let reading = try await capability(processResult(stdout: json)).measure()

    #expect(reading.status == .unavailable)
    #expect(reading.downloadMbps == nil)
    #expect(reading.uploadMbps == nil)
}

@Test("a non-zero exit (no route to the test servers) is an honest unavailable")
func nonZeroExitIsUnavailable() async throws {
    let reading = try await capability(processResult(exitCode: 1, stdout: "")).measure()
    #expect(reading.status == .unavailable)
}

@Test("unparseable output degrades to unavailable rather than crashing")
func garbageOutputIsUnavailable() async throws {
    let reading = try await capability(processResult(stdout: "networkQuality: not JSON")).measure()
    #expect(reading.status == .unavailable)
}

@Test("a timed-out run surfaces as a timeout error, not a fake reading")
func timeoutThrows() async {
    await #expect(throws: NativeCapabilityError.timedOut) {
        _ = try await capability(processResult(timedOut: true)).measure()
    }
}
#endif
