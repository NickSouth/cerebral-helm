import Foundation
import Testing

import CerebralBridge
import CerebralContracts

/// NIC-74a: the portable, transport-agnostic bridge contract — version compatibility,
/// the handshake response, and the inbound-message gate (FR-SHL-06, ADR-004).

private func handshakeRequest(
    uiVersion: String = "0.1.0",
    supportedMajor: Int = 1,
    supportedMinorFloor: Int = 0
) -> CerebralHelmBridgeHandshakeRequest {
    CerebralHelmBridgeHandshakeRequest(
        messageID: "brmsg_uihandshake01",
        schemaVersion: "1.0.0",
        supportedBridgeMajor: supportedMajor,
        supportedBridgeMinorFloor: supportedMinorFloor,
        type: .bridgeHandshakeRequest,
        uiVersion: uiVersion
    )
}

// MARK: - Version compatibility

@Test("matching major with a satisfied minor floor is compatible")
func compatibleVersionsAreAccepted() {
    let result = BridgeCompatibility.evaluate(
        bridgeVersion: "1.0.0", supportedBridgeMajor: 1, supportedBridgeMinorFloor: 0
    )
    #expect(result.compatible)
    #expect(result.reason == nil)
}

@Test("a different major is incompatible")
func majorMismatchIsIncompatible() {
    let result = BridgeCompatibility.evaluate(
        bridgeVersion: "1.0.0", supportedBridgeMajor: 2, supportedBridgeMinorFloor: 0
    )
    #expect(!result.compatible)
    #expect(result.reason != nil)
}

@Test("a minor below the required floor is incompatible")
func minorBelowFloorIsIncompatible() {
    let result = BridgeCompatibility.evaluate(
        bridgeVersion: "1.0.0", supportedBridgeMajor: 1, supportedBridgeMinorFloor: 5
    )
    #expect(!result.compatible)
}

@Test("a non-semantic bridge version is rejected")
func malformedVersionIsIncompatible() {
    #expect(!BridgeCompatibility.evaluate(
        bridgeVersion: "1.0", supportedBridgeMajor: 1, supportedBridgeMinorFloor: 0
    ).compatible)
    #expect(BridgeSemanticVersion("1.2.3") == BridgeSemanticVersion("1.2.3"))
    #expect(BridgeSemanticVersion("nope") == nil)
}

// MARK: - Handshake response

@Test("a compatible handshake reports capabilities and no recovery (FR-SHL-06)")
func compatibleHandshakeReportsCapabilities() {
    let response = BridgeHandshake.response(to: handshakeRequest(), messageID: "brmsg_resp00000001")

    #expect(response.compatible)
    #expect(response.recovery == nil)
    #expect(response.transport == .wkwebview)
    #expect(response.type == .bridgeHandshakeResponse)
    #expect(response.uiVersion == "0.1.0")
    // The bridge/bootstrap capability is native; the deferred natives are unavailable.
    #expect(response.capabilities.contains { $0.id == "bridge.bootstrap" && $0.available })
    #expect(response.capabilities.contains { $0.id == "system.metrics" && !$0.available })
    // Unavailable capabilities become degraded features → startup is degraded, not ready.
    #expect(!response.degradedFeatures.isEmpty)
    #expect(response.startupMode == .degraded)
}

@Test("an empty capability set yields a ready (not degraded) startup")
func readyWhenNothingDegraded() {
    let response = BridgeHandshake.response(
        to: handshakeRequest(), capabilities: [], messageID: "brmsg_resp00000002"
    )
    #expect(response.compatible)
    #expect(response.degradedFeatures.isEmpty)
    #expect(response.startupMode == .ready)
}

@Test("an incompatible major enters read-only recovery with an empty capability set")
func incompatibleHandshakeEntersRecovery() {
    let response = BridgeHandshake.response(
        to: handshakeRequest(supportedMajor: 2), messageID: "brmsg_resp00000003"
    )
    #expect(!response.compatible)
    #expect(response.startupMode == .recovery)
    #expect(response.capabilities.isEmpty)
    #expect(response.recovery?.reason == .majorVersionMismatch)
    #expect(response.recovery?.readOnly == true)
    #expect(response.recovery?.diagnosticCode == "bridge_major_version_mismatch")
}

@Test("the handshake response round-trips through its contract Codable")
func handshakeResponseRoundTrips() throws {
    let response = BridgeHandshake.response(to: handshakeRequest(), messageID: "brmsg_resp00000004")
    let data = try response.jsonData()
    let decoded = try CerebralHelmBridgeHandshakeResponse(data: data)
    #expect(decoded.compatible == response.compatible)
    #expect(decoded.transport == .wkwebview)
    #expect(decoded.capabilities.count == response.capabilities.count)
}

// MARK: - Inbound gate (malformed messages cannot reach core)

@Test("a well-formed handshake request is classified as a handshake")
func classifiesHandshake() throws {
    let data = try handshakeRequest().jsonData()
    guard case .handshake = BridgeInbound.classify(data) else {
        Issue.record("expected .handshake")
        return
    }
}

@Test("a well-formed operation request is classified as an operation")
func classifiesOperation() throws {
    let request = CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_op0000001",
        operation: .submitCommand,
        payload: [:],
        schemaVersion: "1.0.0",
        type: .bridgeOperationRequest
    )
    guard case .operation = BridgeInbound.classify(try request.jsonData()) else {
        Issue.record("expected .operation")
        return
    }
}

@Test("an unknown operation value is rejected as malformed")
func rejectsUnknownOperation() {
    let json = """
    {"schemaVersion":"1.0.0","messageId":"brmsg_op0000002","type":"bridge.operation.request","operation":"frobnicate","payload":{}}
    """
    guard case .malformed = BridgeInbound.classify(Data(json.utf8)) else {
        Issue.record("expected .malformed for an unknown operation")
        return
    }
}

@Test("an unknown message type, non-JSON, and oversized input are all rejected")
func rejectsUnknownTypeNonJSONAndOversize() {
    guard case .malformed = BridgeInbound.classify(Data(#"{"type":"bridge.evil.request"}"#.utf8)) else {
        Issue.record("expected .malformed for unknown type"); return
    }
    guard case .malformed = BridgeInbound.classify(Data("not json".utf8)) else {
        Issue.record("expected .malformed for non-JSON"); return
    }
    let oversized = Data(count: BridgeInbound.maxMessageBytes + 1)
    guard case .malformed = BridgeInbound.classify(oversized) else {
        Issue.record("expected .malformed for oversized input"); return
    }
}
