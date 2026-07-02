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
    return BridgeSession(runtime: try makeCommandRuntime(paths: paths), configDirectory: paths.configDirectory)
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

// MARK: - getBootstrapState

@Test("getBootstrapState composes the four mode views and agent roster from real config")
func bootstrapComposesFromConfig() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.getBootstrapState, "{}"))

    #expect(response.status == .ok)
    #expect(response.error == nil)
    let state = try decode(response, as: CerebralHelmBridgeBootstrapState.self)
    // All four modes are shipped eagerly, derived from config (real ids + themes).
    #expect(state.modes.count == 4)
    #expect(state.modes.contains { $0.id == "developer" })
    #expect(state.modes.contains { $0.theme.accentPrimary.contains("primary") })
    // The fixed global agent roster comes from config.
    #expect(!state.agents.isEmpty)
    // Pre-adapter honesty: regions are empty/unavailable, Heimlich idle, weather nil.
    #expect(state.uiState == .ready)
    #expect(state.heimlich.state == .idle)
    #expect(state.regions.systemHealth.state == .unavailable)
    #expect(state.weather == nil)
}

// MARK: - Knowledge operations

private struct SearchResult: Decodable { struct Hit: Decodable { let noteId: String; let title: String; let excerpt: String }; let results: [Hit] }

@Test("searchNotes finds a note captured through the runtime")
func searchFindsSeededNote() async throws {
    // note.capture is confirmation-gated (local_write), so seed a note by driving the
    // runtime's submit → approve flow directly, then search through the bridge session.
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let runtime = try makeCommandRuntime(paths: paths)
    let pending = await runtime.submit("note Quarterly planning deck", source: .dashboard)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("expected note.capture to await confirmation, got \(pending)")
        return
    }
    _ = await runtime.decide(token: token, decision: .approve)

    let session = BridgeSession(runtime: runtime, configDirectory: paths.configDirectory)
    let searched = await session.execute(operationRequest(.searchNotes, #"{"text":"quarterly"}"#))
    #expect(searched.status == .ok)
    let results = try decode(searched, as: SearchResult.self)
    // The search reaches the live index and returns the seeded note with an id.
    #expect(!results.results.isEmpty)
    #expect(results.results.allSatisfy { !$0.noteId.isEmpty })
}

@Test("an empty search query returns no results (not an error)")
func emptySearchReturnsEmpty() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.searchNotes, #"{"text":""}"#))
    #expect(response.status == .ok)
    #expect(try decode(response, as: SearchResult.self).results.isEmpty)
}

@Test("getRecentActivity returns the honest empty envelope for a fresh session")
func recentActivityEmptyEnvelope() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.getRecentActivity, "{}"))
    #expect(response.status == .ok)
    #expect(response.payload["recentActivity"] != nil)
}

// MARK: - Unwired operations

@Test("an operation not yet wired returns a structured unavailable error, never a hang")
func unwiredOperationIsUnavailable() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.updateSettings, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
    #expect(response.error?.code == "bridge_operation_unimplemented")
}
