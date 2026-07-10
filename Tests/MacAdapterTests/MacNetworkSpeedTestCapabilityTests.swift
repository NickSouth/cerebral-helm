// NIC-135: on-demand internet speed test adapter (Cloudflare / URLSession engine).
//
// The live measurement talks to speed.cloudflare.com, so it is exercised manually
// in the app, not in CI. Here we unit-test the pure throughput math and the
// direction → reading classification. Gated so the Linux CI package build compiles
// this target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralTools
@testable import CerebralMacAdapters

@Test("throughput converts bytes over seconds to Mbps (bytes×8 ÷ seconds ÷ 1e6)")
func throughputConvertsToMbps() {
    // 100 MB in 8 s = 800 Mbit / 8 s = 100 Mbps.
    #expect(MacNetworkSpeedTestCapability.throughputMbps(bytes: 100_000_000, seconds: 8) == 100)
    // 18.125 MB in 1 s ≈ 145 Mbps.
    let mbps = MacNetworkSpeedTestCapability.throughputMbps(bytes: 18_125_000, seconds: 1)
    #expect(mbps != nil && abs(mbps! - 145) < 0.001)
}

@Test("degenerate transfers report no figure rather than dividing by zero")
func degenerateTransfersAreNil() {
    #expect(MacNetworkSpeedTestCapability.throughputMbps(bytes: 0, seconds: 5) == nil)
    #expect(MacNetworkSpeedTestCapability.throughputMbps(bytes: 1000, seconds: 0) == nil)
}

@Test("both directions measured → ok")
func bothDirectionsOk() {
    let reading = MacNetworkSpeedTestCapability.classify(downloadMbps: 145.2, uploadMbps: 17.8)
    #expect(reading.status == .ok)
    #expect(reading.downloadMbps == 145.2)
    #expect(reading.uploadMbps == 17.8)
}

@Test("one direction measured → partial with the other nil")
func oneDirectionPartial() {
    let reading = MacNetworkSpeedTestCapability.classify(downloadMbps: 145.2, uploadMbps: nil)
    #expect(reading.status == .partial)
    #expect(reading.downloadMbps == 145.2)
    #expect(reading.uploadMbps == nil)
}

@Test("no direction measured → unavailable, never a fabricated value")
func noDirectionUnavailable() {
    let reading = MacNetworkSpeedTestCapability.classify(downloadMbps: nil, uploadMbps: nil)
    #expect(reading.status == .unavailable)
    #expect(reading.downloadMbps == nil)
    #expect(reading.uploadMbps == nil)
}
#endif
