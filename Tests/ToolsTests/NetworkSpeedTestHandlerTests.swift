import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-135: the network.speed.test handler maps a capability reading onto its
/// contract output, and translates capability failures to structured errors.

@Test("the handler encodes a measured reading into contract output")
func speedTestHandlerEncodesReading() async throws {
    let handler = NetworkSpeedTestHandler(
        capability: MockNetworkSpeedTestCapability(
            reading: NetworkSpeedTestReading(status: .ok, downloadMbps: 240.5, uploadMbps: 18.2)
        ),
        now: { Date(timeIntervalSince1970: 0) }
    )

    let data = try await handler.execute(input: Data("{}".utf8))
    let output = try CerebralHelmNetworkSpeedTestOutput(data: data)

    #expect(output.status == .ok)
    #expect(output.downloadMbps == 240.5)
    #expect(output.uploadMbps == 18.2)
    #expect(!output.testedAt.isEmpty)
}

@Test("a partial reading round-trips through the contract with one direction nil")
func speedTestHandlerEncodesPartial() async throws {
    let handler = NetworkSpeedTestHandler(
        capability: MockNetworkSpeedTestCapability(
            reading: NetworkSpeedTestReading(status: .partial, downloadMbps: 90, uploadMbps: nil)
        )
    )

    let output = try CerebralHelmNetworkSpeedTestOutput(data: try await handler.execute(input: Data("{}".utf8)))
    #expect(output.status == .partial)
    #expect(output.downloadMbps == 90)
    #expect(output.uploadMbps == nil)
}

@Test("an unavailable capability surfaces as a structured tool error, not a fake value")
func speedTestHandlerUnavailable() async {
    let handler = NetworkSpeedTestHandler(capability: MockNetworkSpeedTestCapability(matrix: .none))
    await #expect(throws: ToolHandlerError.self) {
        _ = try await handler.execute(input: Data("{}".utf8))
    }
}
