import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-74b: `BridgeSession` maps bridge operation requests onto the live
/// `CommandRuntime`. These are integration tests — they build a real runtime over
/// the repository config with an isolated, ephemeral state root, so nothing touches
/// development or personal data (AC-41.1).

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeSession() throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    return BridgeSession(runtime: try makeCommandRuntime(paths: paths))
}

private func payload(_ json: String) -> [String: JSONAny] {
    (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
}

private func operationRequest(
    _ operation: CerebralContracts.Operation, _ json: String, id: String = "brmsg_op0000001"
) -> CerebralHelmBridgeOperationRequest {
    CerebralHelmBridgeOperationRequest(
        messageID: id, operation: operation, payload: payload(json),
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

/// Decodes an operation-response payload back into a typed value for assertions.
private func decode<T: Decodable>(_ response: CerebralHelmBridgeOperationResponse, as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(response.payload)
    return try JSONDecoder().decode(T.self, from: data)
}

private struct Receipt: Decodable { let commandId: String; let accepted: Bool }
private struct ApplyModeResult: Decodable { let modeId: String; let status: String }

// MARK: - submitCommand

@Test("submitCommand runs a recognized command and returns an accepting receipt")
func submitCommandAccepts() async throws {
    let session = try makeSession()
    let response = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"mode developer","source":"dashboard"}"#)
    )

    #expect(response.status == .ok)
    #expect(response.error == nil)
    #expect(response.messageID == "brmsg_op0000001")
    let receipt = try decode(response, as: Receipt.self)
    #expect(receipt.accepted)
    #expect(!receipt.commandId.isEmpty)
}

@Test("submitCommand rejects unrecognized grammar without accepting it")
func submitCommandRejectsUnknown() async throws {
    let session = try makeSession()
    let response = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"please do something vague"}"#)
    )
    #expect(response.status == .ok) // the operation itself succeeded…
    let receipt = try decode(response, as: Receipt.self)
    #expect(!receipt.accepted) // …but the command was not accepted.
}

@Test("submitCommand with an empty rawInput is an invalid-input error")
func submitCommandRequiresInput() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.submitCommand, #"{"rawInput":""}"#))
    #expect(response.status == .error)
    #expect(response.error?.category == .invalidInput)
}

// MARK: - applyMode

@Test("applyMode enters through the command bus and reports ok")
func applyModeRunsThroughBus() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.applyMode, #"{"modeId":"developer"}"#))
    #expect(response.status == .ok)
    let result = try decode(response, as: ApplyModeResult.self)
    #expect(result.modeId == "developer")
    #expect(result.status == "ok")
}

@Test("applyMode requires a modeId")
func applyModeRequiresModeID() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.applyMode, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .invalidInput)
}

// MARK: - Unwired operations

@Test("an operation not yet wired returns a structured unavailable error, never a hang")
func unwiredOperationIsUnavailable() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.getBootstrapState, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
    #expect(response.error?.code == "bridge_operation_unimplemented")
}
