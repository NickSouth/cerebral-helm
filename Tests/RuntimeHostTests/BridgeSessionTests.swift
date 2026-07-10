import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralStorage

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

@Test("applyMode persists the active mode and records a session durably (FR-MOD-05/06)")
func applyModePersistsActiveMode() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths), configDirectory: paths.configDirectory
    )
    let response = await session.execute(operationRequest(.applyMode, #"{"modeId":"developer"}"#))
    #expect(response.status == .ok)

    // The switch reached the operational database: active mode + one session row.
    let database = try operationalDatabase(paths)
    #expect(try SQLiteModeStateStore(database: database).loadActiveModeID() == "developer")
    #expect(try SQLiteModeSessionLog(database: database).read().count == 1)
}

@Test("a raw 'mode <id>' command also re-themes: one switch, one visible result (NIC-85)")
func rawModeCommandEmitsConfigChanged() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        emitEventJSON: { emitted.emit($0) }
    )

    let response = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"mode school","source":"dashboard"}"#)
    )
    #expect(response.status == .ok)

    let configEvents = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "config.changed" }
    let snapshot = (configEvents.first?["payload"] as? [String: Any])?["snapshot"] as? [String: Any]
    #expect(snapshot?["mode"] as? String == "School")
}

@Test("bootstrap restores the last active mode over the stored default (FR-MOD-05)")
func bootstrapRestoresLastActiveMode() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    // The stored default says developer…
    let settings = try makeSettingsStore(paths)
    try settings.apply(SettingsChanges(defaultModeID: "developer"))
    // …but the last active mode was school.
    let first = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory
    )
    _ = await first.execute(operationRequest(.applyMode, #"{"modeId":"school"}"#))

    // A restart restores the last active mode, not the default.
    let second = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        settingsStore: settings,
        modeStateStore: try makeModeStateStore(paths)
    )
    let bootstrap = await second.execute(operationRequest(.getBootstrapState, "{}"))
    let state = try decode(bootstrap, as: CerebralHelmBridgeBootstrapState.self)
    #expect(state.mode == .school)
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

@Test("System Health composes as loading, not unavailable, when live metrics are expected (NIC-136)")
func bootstrapSystemHealthLoadsWhenMetricsAvailable() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    // A composition where the live-metrics provider is bound and permitted.
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        capabilities: [
            CerebralContracts.Capability(available: true, degradedReason: nil, id: "system.metrics", source: .native)
        ]
    )
    let response = await session.execute(operationRequest(.getBootstrapState, "{}"))

    #expect(response.status == .ok)
    let state = try decode(response, as: CerebralHelmBridgeBootstrapState.self)
    // Provider available ⇒ a first sample is inbound ⇒ the region loads (shell renders a
    // same-shape skeleton) rather than flashing unavailable before the sample lands.
    #expect(state.regions.systemHealth.state == .empty)
    #expect(state.regions.systemHealth.battery.state == .empty)
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

// MARK: - listApps

private struct AppsResult: Decodable {
    struct App: Decodable {
        let bundleId: String
        let name: String
        let iconPng: String?
    }
    let apps: [App]
    let truncated: Bool
}

@Test("listApps unwraps the apps.list tool output for the More Apps picker (NIC-119)")
func listAppsReturnsDiscovery() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let runtime = try makeCommandRuntime(paths: paths, phase: .macOS, capabilities: .mocks())
    let session = BridgeSession(runtime: runtime, configDirectory: paths.configDirectory)

    let response = await session.execute(operationRequest(.listApps, "{}"))
    #expect(response.status == .ok)
    let result = try decode(response, as: AppsResult.self)
    #expect(result.apps.map(\.name) == ["Safari", "Mail", "Notes"])
    #expect(result.truncated == false)
}

@Test("listApps auto-mints references so every discovered app is pinnable (owner decision)")
func listAppsMintsAndPins() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let runtime = try makeCommandRuntime(paths: paths, phase: .macOS, capabilities: .mocks())
    let session = BridgeSession(
        runtime: runtime, configDirectory: paths.configDirectory, workspace: paths
    )

    // Discovery mints references for the mock catalog (Safari/Mail/Notes have
    // no shipped reference) — every app comes back reference-backed.
    let response = await session.execute(operationRequest(.listApps, "{}"))
    struct App: Decodable { let name: String; let referenceId: String? }
    struct Result: Decodable { let apps: [App] }
    let result = try decode(response, as: Result.self)
    #expect(result.apps.allSatisfy { $0.referenceId != nil })

    // A freshly minted reference pins through the validated path immediately.
    let safariRef = try #require(result.apps.first { $0.name == "Safari" }?.referenceId)
    let pin = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["\#(safariRef)"]}"#
    ))
    #expect(try decode(pin, as: QuickAppsResult.self).accepted)
    let developer = session.composeBootstrapState().modes.first { $0.id == "developer" }
    #expect(developer?.quickApps == [safariRef])
}

@Test("listApps is a structured unavailable pre-Mac, never a mock success")
func listAppsUnavailablePreMac() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(.listApps, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
}

// MARK: - updateQuickApps (NIC-119c)

private struct QuickAppsResult: Decodable {
    let accepted: Bool
    let quickApps: [String]
    let errors: [String]
}

/// A workspace-bound session: the user-overrides layer is live (bootstrap
/// composes through the loader; updateQuickApps writes overrides).
private func makeWorkspaceSession() throws -> (BridgeSession, WorkspacePaths) {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    )
    return (session, paths)
}

@Test("a pin writes the override through the validated path and bootstrap composes it back (NIC-119c)")
func pinnedQuickAppsSurviveTheReadSide() async throws {
    let (session, paths) = try makeWorkspaceSession()

    let response = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["xcode","terminal"]}"#
    ))
    let result = try decode(response, as: QuickAppsResult.self)
    #expect(result.accepted)
    #expect(result.errors.isEmpty)

    // The override file exists at its canonical path (a manual edit would land
    // in the same place — one write path).
    let overrideURL = paths.overridesDirectory.appendingPathComponent("developer.json")
    #expect(FileManager.default.fileExists(atPath: overrideURL.path))

    // The read side: THIS session and a fresh one both compose the pinned set.
    let developer = session.composeBootstrapState().modes.first { $0.id == "developer" }
    #expect(developer?.quickApps == ["xcode", "terminal"])
    let (restarted, _) = try (BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    ), ())
    let restored = restarted.composeBootstrapState().modes.first { $0.id == "developer" }
    #expect(restored?.quickApps == ["xcode", "terminal"])
}

@Test("an accepted pin emits mode.quickapps.changed carrying the new slots (NIC-149)")
func acceptedPinEmitsQuickAppsChanged() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )

    let response = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["xcode","terminal"]}"#
    ))
    #expect(try decode(response, as: QuickAppsResult.self).accepted)

    let quickAppsEvents = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "mode.quickapps.changed" }
    #expect(quickAppsEvents.count == 1)
    let payload = quickAppsEvents.first?["payload"] as? [String: Any]
    #expect(payload?["modeId"] as? String == "developer")
    #expect(payload?["quickApps"] as? [String] == ["xcode", "terminal"])

    // A rejected write emits nothing — the config is unchanged.
    let rejected = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["/usr/bin/evil"]}"#
    ))
    #expect(try decode(rejected, as: QuickAppsResult.self).accepted == false)
    let after = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "mode.quickapps.changed" }
    #expect(after.count == 1)
}

@Test("a pin naming an unconfigured reference is rejected wholesale (no arbitrary paths)")
func unknownReferenceIsRejected() async throws {
    let (session, paths) = try makeWorkspaceSession()
    let response = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["vscode","/usr/bin/evil"]}"#
    ))
    let result = try decode(response, as: QuickAppsResult.self)
    #expect(!result.accepted)
    #expect(result.errors.count == 1)
    #expect(FileManager.default.fileExists(atPath: paths.overridesDirectory.appendingPathComponent("developer.json").path) == false)
}

@Test("a pin against an unconfigured mode is rejected and rolled back")
func unknownModeIsRejected() async throws {
    let (session, paths) = try makeWorkspaceSession()
    let response = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"garage","quickApps":["vscode"]}"#
    ))
    let result = try decode(response, as: QuickAppsResult.self)
    #expect(!result.accepted)
    #expect(!result.errors.isEmpty)
    #expect(FileManager.default.fileExists(atPath: paths.overridesDirectory.appendingPathComponent("garage.json").path) == false)
}

@Test("a session without a workspace reports pinning unavailable, never a silent no-op")
func pinningWithoutWorkspaceIsUnavailable() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(
        .updateQuickApps,
        #"{"modeId":"developer","quickApps":["vscode"]}"#
    ))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
}

// MARK: - updateSettings

private struct Accepted: Decodable { let accepted: Bool }

/// A session with durable settings over the given workspace, so a second session
/// on the same paths observes the first one's persisted settings (restart shape).
private func makeSessionWithSettings(_ paths: WorkspacePaths) throws -> BridgeSession {
    BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        settingsStore: try makeSettingsStore(paths)
    )
}

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

@Test("an accepted patch is durable: a new session over the same workspace bootstraps the stored default mode")
func acceptedPatchSurvivesRestart() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let first = try makeSessionWithSettings(paths)
    let saved = await first.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_abcd1234","changes":{"defaultModeId":"developer"}}}"#
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)

    // A fresh session over the same workspace (a restart) boots into the stored default.
    let second = try makeSessionWithSettings(paths)
    let bootstrap = await second.execute(operationRequest(.getBootstrapState, "{}"))
    let state = try decode(bootstrap, as: CerebralHelmBridgeBootstrapState.self)
    #expect(state.mode == .developer)
}

@Test("the Windows Stored by Mode toggle persists through the same patch path")
func windowsStoredByModePatchPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_windows001","changes":{"workspace":{"windowsStoredByMode":true}}}}"#
    ))
    #expect(try decode(response, as: Accepted.self).accepted)
    #expect(try makeSettingsStore(paths).load().windowsStoredByMode == true)

    // An unknown workspace key is rejected wholesale.
    let rejected = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"workspace":{"minimizeAll":true}}}}"#
    ))
    #expect(!(try decode(rejected, as: Accepted.self).accepted))
}

@Test("the main-display setting persists through the same patch path (NIC-120b)")
func mainDisplayPatchPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_display001","changes":{"workspace":{"mainDisplayId":"37D8832A-2D66-02CA-B9F7-8F30A301B230"}}}}"#
    ))
    #expect(try decode(response, as: Accepted.self).accepted)
    #expect(try makeSettingsStore(paths).load().mainDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    // An empty display id is rejected wholesale (the contract requires minLength 1).
    let rejected = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"workspace":{"mainDisplayId":""}}}}"#
    ))
    #expect(!(try decode(rejected, as: Accepted.self).accepted))
}

@Test("the assistant name persists through the same patch path and rejects an over-long value (NIC-137)")
func assistantNamePatchPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_name0001","changes":{"appearance":{"assistantName":"Aria"}}}}"#
    ))
    #expect(try decode(response, as: Accepted.self).accepted)
    #expect(try makeSettingsStore(paths).load().appearanceAssistantName == "Aria")

    // Over the 40-character contract bound is rejected wholesale.
    let rejected = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"appearance":{"assistantName":"THIS-ASSISTANT-NAME-IS-DEFINITELY-WAY-TOO-LONG"}}}}"#
    ))
    #expect(!(try decode(rejected, as: Accepted.self).accepted))
}

@Test("per-mode colors persist through the patch path and reject bad keys/values (NIC-137)")
func modeColorsPatchPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_color001","changes":{"modeColors":{"executive.primary":"#ffd166"}}}}"##
    ))
    #expect(try decode(response, as: Accepted.self).accepted)
    #expect(try makeSettingsStore(paths).load().modeColorsJSON?.contains("executive.primary") == true)

    // A non-hex value is rejected wholesale.
    let badValue = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"modeColors":{"executive.primary":"not-a-color"}}}}"#
    ))
    #expect(!(try decode(badValue, as: Accepted.self).accepted))

    // An unknown accent token key is rejected too.
    let badKey = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"changes":{"modeColors":{"executive.tertiary":"#ffffff"}}}}"##
    ))
    #expect(!(try decode(badKey, as: Accepted.self).accepted))
}

@Test("the Ask-before-all-actions flag persists through the patch path and rejects a non-boolean (NIC-137)")
func confirmAllActionsPatchPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_confirm01","changes":{"confirmAllActions":true}}}"#
    ))
    #expect(try decode(response, as: Accepted.self).accepted)
    #expect(try makeSettingsStore(paths).load().confirmAllActions == true)

    // A non-boolean is rejected wholesale.
    let rejected = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"confirmAllActions":"yes"}}}"#
    ))
    #expect(!(try decode(rejected, as: Accepted.self).accepted))
}

@Test("Ask before all actions gates a local_write command that normally runs unconfirmed (NIC-137)")
func confirmAllActionsGatesLocalWrite() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    // Persist the tightening BEFORE composing the runtime — it is read at composition.
    try makeSettingsStore(paths).apply(SettingsChanges(confirmAllActions: true))

    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        emitEventJSON: { emitted.emit($0) }
    )

    // note.capture is local_write — it runs without confirmation by default (see
    // captureNoteReturnsRealId), but the tightening raises it, so the command pauses
    // and a confirmation disclosure is emitted.
    let submit = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"note buy milk","source":"dashboard"}"#)
    )
    #expect(submit.status == .ok)
    let confirmations = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "confirmation.changed" }
    #expect(!confirmations.isEmpty)
}

@Test("a rejected patch persists nothing")
func rejectedPatchPersistsNothing() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    // One valid field alongside one invalid value: the whole patch is rejected.
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"changes":{"defaultModeId":"developer","appearance":{"density":"gigantic"}}}}"#
    ))
    #expect(!(try decode(response, as: Accepted.self).accepted))

    let bootstrap = await session.execute(operationRequest(.getBootstrapState, "{}"))
    let state = try decode(bootstrap, as: CerebralHelmBridgeBootstrapState.self)
    #expect(state.mode == .executive)
}

@Test("a stored default mode that no longer exists in config falls back to the configured default")
func staleStoredModeFallsBack() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let store = try makeSettingsStore(paths)
    try store.apply(SettingsChanges(defaultModeID: "retired-mode"))

    let session = try makeSessionWithSettings(paths)
    let bootstrap = await session.execute(operationRequest(.getBootstrapState, "{}"))
    let state = try decode(bootstrap, as: CerebralHelmBridgeBootstrapState.self)
    #expect(state.mode == .executive)
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

// MARK: - getSettings (NIC-141)

/// A settings snapshot decoded from the getSettings response payload.
private struct SettingsSnapshot: Decodable {
    struct Appearance: Decodable { let reducedMotion: Bool; let assistantName: String }
    struct Knowledge: Decodable { let rootReference: String? }
    struct Workspace: Decodable { let windowsStoredByMode: Bool; let mainDisplayId: String }
    let schemaVersion: String
    let defaultModeId: String
    let confirmAllActions: Bool
    let appearance: Appearance
    let knowledge: Knowledge
    let workspace: Workspace
    let modeColors: [String: String]
}

@Test("getSettings reflects the persisted values written through updateSettings")
func getSettingsReflectsPersistedValues() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let saved = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_read0001","changes":{"defaultModeId":"developer","confirmAllActions":true,"appearance":{"reducedMotion":true,"assistantName":"Aria"},"knowledge":{"rootReference":"primary-vault"},"workspace":{"windowsStoredByMode":true,"mainDisplayId":"37D8832A-2D66-02CA-B9F7-8F30A301B230"},"modeColors":{"executive.primary":"#ffd166"}}}}"##
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)

    // A fresh session over the same workspace (a restart) reads them back on open.
    let reopened = try makeSessionWithSettings(paths)
    let response = await reopened.execute(operationRequest(.getSettings, "{}"))
    #expect(response.status == .ok)
    #expect(response.error == nil)
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.defaultModeId == "developer")
    #expect(snapshot.confirmAllActions == true)
    #expect(snapshot.appearance.reducedMotion == true)
    #expect(snapshot.appearance.assistantName == "Aria")
    #expect(snapshot.modeColors["executive.primary"] == "#ffd166")
    #expect(snapshot.knowledge.rootReference == "primary-vault")
    #expect(snapshot.workspace.windowsStoredByMode == true)
    #expect(snapshot.workspace.mainDisplayId == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
}

@Test("getSettings resolves effective defaults when nothing is stored")
func getSettingsResolvesDefaults() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let response = await session.execute(operationRequest(.getSettings, "{}"))
    #expect(response.status == .ok)
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.defaultModeId == "executive")           // the configured default
    #expect(snapshot.confirmAllActions == false)             // descriptor policy governs
    #expect(snapshot.appearance.reducedMotion == false)
    #expect(snapshot.appearance.assistantName == "Heimlich")  // the default identity
    #expect(snapshot.modeColors.isEmpty)                      // no overrides stored
    #expect(snapshot.knowledge.rootReference == nil)
    #expect(snapshot.workspace.windowsStoredByMode == false)
    #expect(snapshot.workspace.mainDisplayId == "system-primary")
}

@Test("getSettings is the default-mode setting, not the currently active mode")
func getSettingsReturnsSettingNotActiveMode() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    // Persist developer as the default; then switch the ACTIVE mode to school.
    _ = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_read0002","changes":{"defaultModeId":"developer"}}}"#
    ))
    _ = await session.execute(operationRequest(.applyMode, #"{"modeId":"school"}"#))

    let response = await session.execute(operationRequest(.getSettings, "{}"))
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    // The "Default mode" setting is unchanged by an active-mode switch.
    #expect(snapshot.defaultModeId == "developer")
}

@Test("getSettings degrades to defaults (never errors) with no settings store bound")
func getSettingsWithoutStoreDegrades() async throws {
    let session = try makeSession() // no settingsStore
    let response = await session.execute(operationRequest(.getSettings, "{}"))
    #expect(response.status == .ok)
    #expect(response.error == nil)
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.defaultModeId == "executive")
    #expect(snapshot.workspace.mainDisplayId == "system-primary")
}

// MARK: - runSpeedTest (NIC-135)

/// Builds a session at a chosen execution phase; the network.speed.test tool is
/// `macos_native`, so only a macOS-phase runtime executes it.
private func makeSession(phase: ExecutionPhase) throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    return BridgeSession(runtime: try makeCommandRuntime(paths: paths, phase: phase), configDirectory: paths.configDirectory)
}

private struct SpeedTestResult: Decodable {
    let status: String
    let downloadMbps: Double?
    let uploadMbps: Double?
    let testedAt: String?
}

@Test("runSpeedTest returns the measured capacity from the tool (macOS phase)")
func runSpeedTestReturnsMeasurement() async throws {
    // The .mocks() bundle backs network.speed.test with a deterministic reading.
    let session = try makeSession(phase: .macOS)
    let response = await session.execute(operationRequest(.runSpeedTest, "{}"))

    #expect(response.status == .ok)
    #expect(response.error == nil)
    let result = try decode(response, as: SpeedTestResult.self)
    #expect(result.status == "ok")
    #expect(result.downloadMbps == 240)
    #expect(result.uploadMbps == 18)
    #expect(!(result.testedAt ?? "").isEmpty)
}

@Test("runSpeedTest degrades to unavailable when the native tool is absent (pre-Mac)")
func runSpeedTestUnavailablePreMac() async throws {
    // network.speed.test is macOS-only; a pre-Mac runtime cannot run it, so the
    // operation reports an honest unavailable rather than hanging or crashing.
    let session = try makeSession(phase: .preMac)
    let response = await session.execute(operationRequest(.runSpeedTest, "{}"))

    #expect(response.status == .ok)
    let result = try decode(response, as: SpeedTestResult.self)
    #expect(result.status == "unavailable")
    #expect(result.downloadMbps == nil)
    #expect(result.uploadMbps == nil)
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
