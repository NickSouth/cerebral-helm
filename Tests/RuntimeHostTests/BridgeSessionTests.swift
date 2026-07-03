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

@Test("applyMode re-themes by emitting the target mode's config.changed snapshot")
func applyModeEmitsConfigChanged() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        emitEventJSON: { emitted.emit($0) }
    )
    let response = await session.execute(operationRequest(.applyMode, #"{"modeId":"developer"}"#))
    #expect(response.status == .ok)
    #expect(try decode(response, as: ApplyModeResult.self).status == "ok")

    // A config.changed event with the target mode snapshot was pushed (no confirmation).
    let configEvents = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "config.changed" }
    #expect(!configEvents.isEmpty)
    let snapshot = (configEvents.first?["payload"] as? [String: Any])?["snapshot"] as? [String: Any]
    #expect(snapshot?["mode"] as? String == "Developer")
}

@Test("applyMode rejects an unknown mode and requires a modeId")
func applyModeValidatesMode() async throws {
    let session = try makeSession()
    let missing = await session.execute(operationRequest(.applyMode, "{}"))
    #expect(missing.error?.category == .invalidInput)

    let unknown = await session.execute(operationRequest(.applyMode, #"{"modeId":"nope"}"#))
    #expect(unknown.status == .ok)
    #expect(try decode(unknown, as: ApplyModeResult.self).status == "error")
}

// MARK: - getBootstrapState

@Test("getBootstrapState composes the four mode views and agent roster from real config")
func bootstrapComposesFromConfig() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.getBootstrapState, "{}"))

    #expect(response.status == .ok)
    #expect(response.error == nil)
    let state = try decode(response, as: CerebralHelmBridgeBootstrapState.self)
    // All four modes are shipped eagerly, derived from config (real ids + themes),
    // in the canonical display order (not alphabetical config-file order).
    #expect(state.modes.map(\.id) == ["executive", "developer", "school", "entertainment"])
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
    // note.capture is local_write and runs without confirmation, so seed a note by
    // submitting directly, then search through the bridge session.
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let runtime = try makeCommandRuntime(paths: paths)
    let outcome = await runtime.submit("note Quarterly planning deck", source: .dashboard)
    guard case .completed = outcome else {
        Issue.record("expected note capture to complete, got \(outcome)")
        return
    }

    let session = BridgeSession(runtime: runtime, configDirectory: paths.configDirectory)
    let searched = await session.execute(operationRequest(.searchNotes, #"{"text":"quarterly"}"#))
    #expect(searched.status == .ok)
    let results = try decode(searched, as: SearchResult.self)
    // The search reaches the live index and returns the seeded note with an id.
    #expect(!results.results.isEmpty)
    #expect(results.results.allSatisfy { !$0.noteId.isEmpty })
}

private struct NoteId: Decodable { let noteId: String }

@Test("captureNote writes a note and returns its real id (local_write runs without confirmation)")
func captureNoteReturnsRealId() async throws {
    let session = try makeSession()
    let response = await session.execute(
        operationRequest(.captureNote, #"{"title":"Quarterly planning","body":"Draft the deck."}"#)
    )
    #expect(response.status == .ok)
    let noteId = try decode(response, as: NoteId.self).noteId
    // A completed capture returns the note's id, not a command handle (no confirmation).
    #expect(!noteId.isEmpty)
    #expect(!noteId.hasPrefix("cmd_"))
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

// MARK: - Confirmation flow

/// Thread-safe collector for emitted bridge-event JSON strings.
private final class EmittedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func emit(_ json: String) { lock.lock(); defer { lock.unlock() }; events.append(json) }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
}

@Test("a gated command emits a confirmation disclosure, and decideConfirmation resolves it")
func confirmationFlow() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        emitEventJSON: { emitted.emit($0) }
    )

    // hook.run (shell) is a gated class, so it pauses for confirmation.
    let submit = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"hook ondraft-dev","source":"dashboard"}"#)
    )
    #expect(submit.status == .ok)

    // A confirmation.changed event carrying the disclosure was pushed to the UI.
    let confirmationEvents = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "confirmation.changed" }
    #expect(!confirmationEvents.isEmpty)

    // Extract the disclosure id the dashboard would decide on.
    let disclosure = (confirmationEvents.first?["payload"] as? [String: Any])?["confirmation"] as? [String: Any]
    let id = try #require(disclosure?["id"] as? String)

    // Decide it: approve → resolves, returns the id, and clears the confirmation.
    let decided = await session.execute(
        operationRequest(.decideConfirmation, #"{"id":"\#(id)","decision":"approve"}"#)
    )
    #expect(decided.status == .ok)

    // A clearing confirmation.changed event (no disclosure) followed the decision.
    let cleared = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "confirmation.changed" }
    #expect(cleared.count >= 2)
    let lastConfirmation = (cleared.last?["payload"] as? [String: Any])?["confirmation"]
    #expect(lastConfirmation == nil) // absent/null == cleared
}

@Test("deciding an unknown confirmation id fails closed")
func decideUnknownConfirmation() async throws {
    let session = try makeSession()
    let response = await session.execute(
        operationRequest(.decideConfirmation, #"{"id":"conf_does_not_exist","decision":"approve"}"#)
    )
    #expect(response.status == .error)
    #expect(response.error?.code == "unknown_confirmation")
}

// MARK: - updateSettings (validate-only)

private struct Accepted: Decodable { let accepted: Bool }

@Test("a valid settings patch is accepted")
func validSettingsPatchAccepted() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_abcd1234","changes":{"defaultModeId":"developer","appearance":{"density":"compact"}}}}"#
    ))
    #expect(response.status == .ok)
    #expect(try decode(response, as: Accepted.self).accepted)
}

@Test("a policy-weakening key is rejected — settings cannot widen risk (ADR-003)")
func riskOverridePatchRejected() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"toolRiskOverrides":{"hook.run":"read_only"}}}}"#
    ))
    #expect(response.status == .ok)
    #expect(!(try decode(response, as: Accepted.self).accepted))
}

@Test("an invalid value is rejected")
func invalidSettingsValueRejected() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(
        .updateSettings, #"{"patch":{"changes":{"appearance":{"density":"gigantic"}}}}"#
    ))
    #expect(!(try decode(response, as: Accepted.self).accepted))
}

@Test("updateSettings without a patch is an invalid-input error")
func updateSettingsRequiresPatch() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.updateSettings, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .invalidInput)
}

// MARK: - Unwired operations

@Test("an operation not yet wired returns a structured unavailable error, never a hang")
func unwiredOperationIsUnavailable() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.subscribe, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
    #expect(response.error?.code == "bridge_operation_unimplemented")
}
