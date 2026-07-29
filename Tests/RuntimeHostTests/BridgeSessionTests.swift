import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralStorage
import CerebralTools

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

@Test("a re-pointed knowledge root stores captured notes at the override location (NIC-138)")
func knowledgeRootRepointStoresNotes() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    // An override folder distinct from the env default, persisted BEFORE composition.
    let overrideRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ch-knowledge-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: overrideRoot) }
    try makeSettingsStore(paths).apply(SettingsChanges(knowledgeRootReference: overrideRoot.path))

    // Composed after persisting → the runtime points knowledge at the override.
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory
    )
    let response = await session.execute(
        operationRequest(.captureNote, #"{"title":"Plan","body":"Draft the deck."}"#)
    )
    #expect(response.status == .ok)

    // The Markdown note lands under the override root, and never under the env default —
    // a re-point, not a copy.
    let overrideMd = (try? FileManager.default.subpathsOfDirectory(atPath: overrideRoot.path)) ?? []
    #expect(overrideMd.contains { $0.hasSuffix(".md") })
    let defaultMd = (try? FileManager.default.subpathsOfDirectory(atPath: paths.knowledgeRoot.path)) ?? []
    #expect(!defaultMd.contains { $0.hasSuffix(".md") })
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
// MARK: - Layout session (NIC-142)

private struct CloseLayoutResult: Decodable { let closed: Bool }
private struct ToggleLayoutResult: Decodable { let accepted: Bool }
private struct PinLayoutWindowResult: Decodable { let accepted: Bool }
private struct AddLayoutTargetResult: Decodable { let accepted: Bool }
private struct UpdateLayoutResult: Decodable { let accepted: Bool }
private struct CaptureLayoutResult: Decodable {
    struct Window: Decodable { let ref: String; let kind: String; let frame: String }
    let windows: [Window]
}

private func activeToggleTargets(_ emitted: EmittedEvents) -> [String] {
    let last = layoutSessionEvents(emitted).last?["payload"] as? [String: Any]
    let toggle = (last?["session"] as? [String: Any])?["quickToggle"] as? [String: Any]
    let targets = toggle?["targets"] as? [[String: Any]] ?? []
    return targets.compactMap { $0["ref"] as? String }
}

/// Records the bundle ids hidden through the workspace-windows capability so a test
/// can assert which app windows `closeLayout` hid.
private final class RecordingWorkspaceWindows: WorkspaceWindowsCapability, @unchecked Sendable {
    private(set) var hidden: [String] = []
    func visibleApplicationBundleIDs() async throws -> [String] { [] }
    func hideApplications(bundleIDs: [String]) async throws -> [String] {
        hidden.append(contentsOf: bundleIDs)
        return bundleIDs
    }
    func unhideApplications(bundleIDs: [String]) async throws -> [String] { bundleIDs }
}

private func layoutSessionEvents(_ emitted: EmittedEvents) -> [[String: Any]] {
    emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "layout.session.changed" }
}

@Test("openLayout starts a session from the mode's authored layout and emits it")
func openLayoutEmitsSession() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )

    let response = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    #expect(response.status == .ok)

    let events = layoutSessionEvents(emitted)
    #expect(events.count >= 1)
    let sess = (events.first?["payload"] as? [String: Any])?["session"] as? [String: Any]
    #expect(sess?["modeId"] as? String == "developer")
    let windows = sess?["windows"] as? [[String: Any]]
    #expect(windows?.contains { $0["ref"] as? String == "claude-desktop" } == true)
    let toggle = sess?["quickToggle"] as? [String: Any]
    #expect(toggle?["activeRef"] as? String == "vscode")
}

@Test("openLayout for a mode with no authored layout is an honest error")
func openLayoutNoLayoutErrors() async throws {
    let session = try makeSession()
    // Executive ships no layout (NIC-142 — Executive has no layout mode).
    let response = await session.execute(operationRequest(.openLayout, #"{"modeId":"executive"}"#))
    #expect(response.status == .error)
    #expect(response.error?.code == "no_layout")
}

@Test("closeLayout hides the session's app windows and ends the session")
func closeLayoutHidesAndEnds() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let windows = RecordingWorkspaceWindows()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: windows,
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    let close = await session.execute(operationRequest(.closeLayout, "{}"))
    #expect(try decode(close, as: CloseLayoutResult.self).closed)

    // The developer layout's app windows (Claude, VS Code) were hidden.
    #expect(!windows.hidden.isEmpty)
    // The final layout event ends the session (session: null).
    let events = layoutSessionEvents(emitted)
    #expect((events.last?["payload"] as? [String: Any])?["session"] is NSNull)
}

@Test("closeLayout with no active session is a no-op that reports not-closed")
func closeLayoutNoSessionIsNoOp() async throws {
    let session = try makeSession()
    let close = await session.execute(operationRequest(.closeLayout, "{}"))
    #expect(try !decode(close, as: CloseLayoutResult.self).closed)
}

@Test("a mode switch ends an active layout session (NIC-142)")
func modeSwitchEndsLayoutSession() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    _ = await session.execute(operationRequest(.applyMode, #"{"modeId":"school"}"#))

    // The switch emitted a session-ending (null) layout event.
    let events = layoutSessionEvents(emitted)
    #expect(events.contains { ($0["payload"] as? [String: Any])?["session"] is NSNull })
}

@Test("toggleLayout swaps the dynamic slot, hides the previous app, and emits the new active")
func toggleLayoutSwapsSlot() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let windows = RecordingWorkspaceWindows()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: windows,
        app: MockAppCapability(),
        url: MockURLCapability(),
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    // Developer's slot starts on vscode (app); toggle to github (url).
    let toggle = await session.execute(operationRequest(.toggleLayout, #"{"ref":"github"}"#))
    #expect(try decode(toggle, as: ToggleLayoutResult.self).accepted)

    // The previously-shown app (VS Code) was hidden.
    #expect(!windows.hidden.isEmpty)
    // The layout event now shows github as the active toggle target.
    let last = layoutSessionEvents(emitted).last?["payload"] as? [String: Any]
    let toggleState = (last?["session"] as? [String: Any])?["quickToggle"] as? [String: Any]
    #expect(toggleState?["activeRef"] as? String == "github")
}

@Test("toggling to the already-shown target is an accepted no-op (no re-emit)")
func toggleLayoutSameTargetNoOp() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        app: MockAppCapability(),
        url: MockURLCapability(),
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    let before = layoutSessionEvents(emitted).count
    // vscode is already the active target.
    let toggle = await session.execute(operationRequest(.toggleLayout, #"{"ref":"vscode"}"#))
    #expect(try decode(toggle, as: ToggleLayoutResult.self).accepted)
    #expect(layoutSessionEvents(emitted).count == before)  // no new layout event
}

@Test("toggleLayout with no active session is not accepted")
func toggleLayoutNoSession() async throws {
    let session = try makeSession()
    let toggle = await session.execute(operationRequest(.toggleLayout, #"{"ref":"github"}"#))
    #expect(try !decode(toggle, as: ToggleLayoutResult.self).accepted)
}

@Test("pinLayoutWindow adds a toggle target, refreshes the session, and persists to the next open (NIC-142)")
func pinLayoutWindowPersistsAndRefreshes() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    // Terminal is a configured app reference; pin it as a new toggle target.
    let pin = await session.execute(operationRequest(.pinLayoutWindow, #"{"modeId":"developer","ref":"terminal"}"#))
    #expect(try decode(pin, as: PinLayoutWindowResult.self).accepted)
    // The active session picked up the new target immediately.
    #expect(activeToggleTargets(emitted).contains("terminal"))

    // A fresh session's open reads the override-merged layout — the pin persisted.
    let reopened = EmittedEvents()
    let session2 = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { reopened.emit($0) }
    )
    _ = await session2.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    #expect(activeToggleTargets(reopened).contains("terminal"))
}

@Test("updateLayout writes a full authored layout and persists it to the next open (NIC-142)")
func updateLayoutPersists() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    )

    let payload = #"""
    {"modeId":"developer","layout":{"display":"secondary",
      "windows":[{"ref":"vscode","kind":"app","frame":"left-half"}],
      "quickToggle":{"frame":"right-half","targets":[{"ref":"claude-desktop","kind":"app"}]}}}
    """#
    let response = await session.execute(operationRequest(.updateLayout, payload))
    #expect(try decode(response, as: UpdateLayoutResult.self).accepted)

    // A fresh open reads the override-merged layout — the authored layout persisted.
    let reopened = EmittedEvents()
    let session2 = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { reopened.emit($0) }
    )
    _ = await session2.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    #expect(activeToggleTargets(reopened) == ["claude-desktop"])
}

@Test("updateLayout rejects a layout referencing an unknown app")
func updateLayoutUnknownRef() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    )
    let payload = #"{"modeId":"developer","layout":{"display":"primary","windows":[{"ref":"ghost-app","kind":"app","frame":"full"}]}}"#
    let response = await session.execute(operationRequest(.updateLayout, payload))
    #expect(try !decode(response, as: UpdateLayoutResult.self).accepted)
}

@Test("captureLayout proposes named frames snapped from the visible windows (NIC-142)")
func captureLayoutProposes() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let visible = WindowRect(x: 0, y: 0, width: 1200, height: 800)
    let windowCap = MockWindowCapability(
        capturedFrames: ["com.microsoft.VSCode": WindowRect(x: 0, y: 0, width: 800, height: 800)],
        visibleDisplayFrame: visible
    )
    let workspaceWindows = MockWorkspaceWindowsCapability(visibleBundleIDs: ["com.microsoft.VSCode"])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: workspaceWindows,
        window: windowCap
    )

    let response = await session.execute(operationRequest(.captureLayout, "{}"))
    let windows = try decode(response, as: CaptureLayoutResult.self).windows
    #expect(windows.contains { $0.ref == "vscode" && $0.frame == "left-two-thirds" })
}

@Test("captureLayout without the AX capability degrades honestly")
func captureLayoutUnavailable() async throws {
    let session = try makeSession()  // no window capability
    let response = await session.execute(operationRequest(.captureLayout, "{}"))
    #expect(response.status == .error)
    #expect(response.error?.code == "capture_unavailable")
}

@Test("pinLayoutWindow rejects an unknown reference")
func pinLayoutWindowUnknownRef() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    )
    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    let pin = await session.execute(operationRequest(.pinLayoutWindow, #"{"modeId":"developer","ref":"not-a-real-ref"}"#))
    #expect(try !decode(pin, as: PinLayoutWindowResult.self).accepted)
}

@Test("pinLayoutWindow preserves a mode's existing quick-apps override")
func pinLayoutWindowPreservesQuickApps() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths
    )
    // First pin a quick app, then a layout window not already in the slot; the
    // layout write must keep the quick-apps override.
    _ = await session.execute(operationRequest(.updateQuickApps, #"{"modeId":"developer","quickApps":["vscode"]}"#))
    _ = await session.execute(operationRequest(.pinLayoutWindow, #"{"modeId":"developer","ref":"terminal"}"#))

    let override = try CerebralHelmModeOverride(
        data: Data(contentsOf: paths.overridesDirectory.appendingPathComponent("developer.json"))
    )
    #expect(override.quickApps == ["vscode"])
    #expect(override.layout != nil)
}

@Test("addLayoutTarget adds a session-only toggle target, emits it, and does NOT persist (NIC-142)")
func addLayoutTargetSessionOnly() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )

    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    // Terminal is a configured app reference and not already a toggle target.
    let add = await session.execute(operationRequest(.addLayoutTarget, #"{"ref":"terminal"}"#))
    #expect(try decode(add, as: AddLayoutTargetResult.self).accepted)
    #expect(activeToggleTargets(emitted).contains("terminal"))

    // Session-only: nothing was written to the mode override (contrast pinLayoutWindow).
    #expect(
        !FileManager.default.fileExists(
            atPath: paths.overridesDirectory.appendingPathComponent("developer.json").path
        )
    )
}

@Test("addLayoutTarget is idempotent for a ref already in the slot")
func addLayoutTargetIdempotent() async throws {
    let session = try makeSession()
    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    // vscode is the developer layout's initial toggle target.
    let add = await session.execute(operationRequest(.addLayoutTarget, #"{"ref":"vscode"}"#))
    #expect(try decode(add, as: AddLayoutTargetResult.self).accepted)
}

@Test("addLayoutTarget with no active session is not accepted")
func addLayoutTargetNoSession() async throws {
    let session = try makeSession()
    let add = await session.execute(operationRequest(.addLayoutTarget, #"{"ref":"terminal"}"#))
    #expect(try !decode(add, as: AddLayoutTargetResult.self).accepted)
}

@Test("addLayoutTarget rejects an unknown reference")
func addLayoutTargetUnknownRef() async throws {
    let session = try makeSession()
    _ = await session.execute(operationRequest(.openLayout, #"{"modeId":"developer"}"#))
    let add = await session.execute(operationRequest(.addLayoutTarget, #"{"ref":"not-a-real-ref"}"#))
    #expect(try !decode(add, as: AddLayoutTargetResult.self).accepted)
}

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

@Test("listApps live-reloads references so a freshly discovered app opens this session (NIC-150)")
func listAppsMakesDiscoveredAppOpenableWithoutRestart() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let runtime = try makeCommandRuntime(paths: paths, phase: .macOS, capabilities: .mocks())
    let session = BridgeSession(
        runtime: runtime, configDirectory: paths.configDirectory, workspace: paths
    )

    // Safari has no shipped reference and nothing is minted into the fresh state
    // root yet, so `open safari` is unrecognized before discovery runs — this is
    // the just-installed baseline (the reference store composes at startup).
    let before = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"open safari"}"#)
    )
    #expect(try !decode(before, as: Receipt.self).accepted)

    // Discovery mints `safari` and live-reloads the shared catalog…
    _ = await session.execute(operationRequest(.listApps, "{}"))

    // …so the same command now resolves this session — no relaunch.
    let after = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"open safari"}"#)
    )
    #expect(try decode(after, as: Receipt.self).accepted)
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

// MARK: - URL references (NIC-146)

private struct UrlRefDTO: Decodable { let id: String; let label: String; let target: String; let iconPng: String?; let profile: String? }
private struct AddUrlResult: Decodable { let accepted: Bool; let reference: UrlRefDTO?; let errors: [String] }
private struct ListUrlsResult: Decodable { let urls: [UrlRefDTO] }
private struct AppRefDTO: Decodable { let id: String; let label: String; let target: String; let profile: String? }
private struct AddChromeProfileResult: Decodable { let accepted: Bool; let reference: AppRefDTO?; let errors: [String] }

@Test("addChromeProfileReference mints a Chrome-targeted app reference that pins and opens (NIC-151)")
func addChromeProfileReferenceMintsAndPins() async throws {
    let (session, _) = try makeWorkspaceSession()
    let added = try decode(await session.execute(operationRequest(
        .addChromeProfileReference,
        #"{"directory":"Profile 1","name":"Work"}"#
    )), as: AddChromeProfileResult.self)
    #expect(added.accepted)
    #expect(added.reference?.id == "chrome-work")
    #expect(added.reference?.target == "com.google.Chrome")
    #expect(added.reference?.profile == "Profile 1")

    // The minted id pins through the same validated path an app id clears…
    let refId = try #require(added.reference?.id)
    let pin = try decode(await session.execute(operationRequest(
        .updateQuickApps, #"{"modeId":"developer","quickApps":["\#(refId)"]}"#
    )), as: QuickAppsResult.self)
    #expect(pin.accepted)

    // …and the parser resolves `open <id>` this same session (catalog reload).
    let opened = try decode(await session.execute(operationRequest(
        .submitCommand, #"{"rawInput":"open \#(refId)"}"#
    )), as: Receipt.self)
    #expect(opened.accepted)
}

@Test("addChromeProfileReference refuses an empty directory without minting (NIC-151)")
func addChromeProfileReferenceRefusesEmpty() async throws {
    let (session, _) = try makeWorkspaceSession()
    let result = try decode(await session.execute(operationRequest(
        .addChromeProfileReference, #"{"directory":""}"#
    )), as: AddChromeProfileResult.self)
    #expect(!result.accepted)
    #expect(result.reference == nil)
    #expect(!result.errors.isEmpty)
}

@Test("addUrlReference mints an http URL and lists it back alongside shipped ones (NIC-146)")
func addUrlReferenceMintsAndLists() async throws {
    let (session, _) = try makeWorkspaceSession()
    let added = try decode(await session.execute(operationRequest(
        .addURLReference,
        #"{"url":"https://news.ycombinator.com","label":"Hacker News"}"#
    )), as: AddUrlResult.self)
    #expect(added.accepted)
    #expect(added.reference?.id == "hacker-news")
    #expect(added.reference?.target == "https://news.ycombinator.com")

    let listed = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(listed.urls.contains { $0.id == "hacker-news" })
    #expect(listed.urls.contains { $0.id == "github" }) // shipped catalog is included
}

@Test("addUrlReference carries a Chrome profile through the mint and lists it back (NIC-151)")
func addUrlReferenceWithProfile() async throws {
    let (session, _) = try makeWorkspaceSession()
    let added = try decode(await session.execute(operationRequest(
        .addURLReference,
        #"{"url":"https://mail.google.com","label":"Work Mail","profile":"Profile 1"}"#
    )), as: AddUrlResult.self)
    #expect(added.accepted)
    #expect(added.reference?.profile == "Profile 1")

    // The profile round-trips through the read feed so the tile/form can show it.
    let listed = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(listed.urls.first { $0.id == added.reference?.id }?.profile == "Profile 1")
    // Shipped, profile-less references still omit the field.
    #expect(listed.urls.first { $0.id == "github" }?.profile == nil)
}

@Test("addUrlReference rejects a flag-injecting Chrome profile without minting (NIC-151)")
func addUrlReferenceRejectsInvalidProfile() async throws {
    let (session, _) = try makeWorkspaceSession()
    let result = try decode(await session.execute(operationRequest(
        .addURLReference,
        #"{"url":"https://mail.google.com","label":"Work Mail","profile":"Default --load-extension=/tmp/evil"}"#
    )), as: AddUrlResult.self)
    #expect(!result.accepted)
    #expect(result.reference == nil)
    #expect(!result.errors.isEmpty)

    // Nothing was minted, so the read feed never carries the rejected profile.
    let listed = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(!listed.urls.contains { $0.target == "https://mail.google.com" })
}

@Test("a minted URL reference pins as a quick app through the same validated path (NIC-146)")
func mintedUrlPinsAsQuickApp() async throws {
    let (session, _) = try makeWorkspaceSession()
    let minted = try decode(await session.execute(operationRequest(
        .addURLReference, #"{"url":"https://example.com","label":"Example"}"#
    )), as: AddUrlResult.self)
    let refId = try #require(minted.reference?.id)

    // The URL id clears the same updateQuickApps existence check an app id does,
    // and composes back through the read side mixed with an app reference.
    let pin = try decode(await session.execute(operationRequest(
        .updateQuickApps, #"{"modeId":"developer","quickApps":["\#(refId)","vscode"]}"#
    )), as: QuickAppsResult.self)
    #expect(pin.accepted)
    let developer = session.composeBootstrapState().modes.first { $0.id == "developer" }
    #expect(developer?.quickApps == [refId, "vscode"])
}

@Test("a minted URL is openable in the same session — the catalog reloads after the mint (NIC-146)")
func mintedUrlIsImmediatelyOpenable() async throws {
    let (session, _) = try makeWorkspaceSession()

    // Before the mint the id is unknown to the parser, so `open` is rejected.
    let before = try decode(await session.execute(operationRequest(
        .submitCommand, #"{"rawInput":"open example-live"}"#
    )), as: Receipt.self)
    #expect(!before.accepted)

    let minted = try decode(await session.execute(operationRequest(
        .addURLReference, #"{"url":"https://example.live","label":"Example Live"}"#
    )), as: AddUrlResult.self)
    #expect(minted.reference?.id == "example-live")

    // After the mint the parser resolves `open <id>` this same session (reference
    // reload) — the command is accepted onto the bus, no relaunch required.
    let after = try decode(await session.execute(operationRequest(
        .submitCommand, #"{"rawInput":"open example-live"}"#
    )), as: Receipt.self)
    #expect(after.accepted)
}

@Test("addUrlReference refuses a non-web scheme without minting (NIC-146)")
func addUrlReferenceRefusesNonWebScheme() async throws {
    let (session, _) = try makeWorkspaceSession()
    let result = try decode(await session.execute(operationRequest(
        .addURLReference, #"{"url":"file:///etc/passwd"}"#
    )), as: AddUrlResult.self)
    #expect(!result.accepted)
    #expect(result.reference == nil)
    #expect(!result.errors.isEmpty)

    // It never entered the catalog — listUrls only ever returns web targets.
    let listed = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(listed.urls.allSatisfy { $0.target.hasPrefix("http") })
}

@Test("addUrlReference without a workspace is unavailable, never a silent mint (NIC-146)")
func addUrlReferenceWithoutWorkspaceUnavailable() async throws {
    let session = try makeSession()
    let response = await session.execute(operationRequest(
        .addURLReference, #"{"url":"https://example.com"}"#
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

@Test("updateSettings emits settings.changed carrying the new snapshot for live sync (NIC-137)")
func updateSettingsEmitsSettingsChanged() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        settingsStore: try makeSettingsStore(paths),
        emitEventJSON: { emitted.emit($0) }
    )
    let response = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_sync0001","changes":{"appearance":{"assistantName":"Cerebra"}}}}"#
    ))
    #expect(try decode(response, as: Accepted.self).accepted)

    // The event carries the full resolved snapshot so every surface can re-sync live.
    let events = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "settings.changed" }
    #expect(events.count == 1)
    let settings = (events.first?["payload"] as? [String: Any])?["settings"] as? [String: Any]
    let appearance = settings?["appearance"] as? [String: Any]
    #expect(appearance?["assistantName"] as? String == "Cerebra")
}

@Test("toggling Ask before all actions re-arms confirmation live, without a relaunch (NIC-137)")
func confirmAllActionsReArmsLive() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        settingsStore: try makeSettingsStore(paths),
        emitEventJSON: { emitted.emit($0) }
    )
    func confirmationCount() -> Int {
        emitted.all()
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .filter { ($0["type"] as? String) == "confirmation.changed" }
            .count
    }

    // Flag off: a local_write note runs without confirmation.
    let before = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"note first","source":"dashboard"}"#)
    )
    #expect(before.status == .ok)
    #expect(confirmationCount() == 0)

    // Toggle it ON through the SAME live session — no relaunch.
    let toggle = await session.execute(operationRequest(
        .updateSettings,
        #"{"patch":{"schemaVersion":"1.0.0","patchId":"set_rearm001","changes":{"confirmAllActions":true}}}"#
    ))
    #expect(try decode(toggle, as: Accepted.self).accepted)

    // The next identical note now pauses for confirmation — the tightening applied live.
    let after = await session.execute(
        operationRequest(.submitCommand, #"{"rawInput":"note second","source":"dashboard"}"#)
    )
    #expect(after.status == .ok)
    #expect(confirmationCount() >= 1)
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

/// Records the changes handed to `onSettingsChanged` from a `@Sendable` closure (NIC-128).
private final class SettingsChangeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var last: SettingsChanges?
    func record(_ changes: SettingsChanges) { lock.lock(); last = changes; lock.unlock() }
    var tickersChanged: Bool { lock.lock(); defer { lock.unlock() }; return last?.stockTickersJSON != nil }
    var fired: Bool { lock.lock(); defer { lock.unlock() }; return last != nil }
}

@Test("updateSettings fires onSettingsChanged with the applied changes so a producer can refresh (NIC-128)")
func updateSettingsFiresOnSettingsChanged() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let box = SettingsChangeBox()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        settingsStore: try makeSettingsStore(paths),
        onSettingsChanged: { box.record($0) }
    )
    let saved = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_stocks03","changes":{"stocks":{"tickers":["SPY","QQQ"]}}}}"##
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)
    #expect(box.tickersChanged) // the hook saw the ticker change, so the producer can re-sample
}

// MARK: - getSettings (NIC-141)

/// A settings snapshot decoded from the getSettings response payload.
private struct SettingsSnapshot: Decodable {
    struct Appearance: Decodable { let reducedMotion: Bool; let assistantName: String }
    struct Knowledge: Decodable { let rootReference: String? }
    struct Workspace: Decodable { let windowsStoredByMode: Bool; let mainDisplayId: String }
    struct Stocks: Decodable { let tickers: [String] }
    let schemaVersion: String
    let defaultModeId: String
    let confirmAllActions: Bool
    let appearance: Appearance
    let knowledge: Knowledge
    let workspace: Workspace
    let modeColors: [String: String]
    let stocks: Stocks
    let calendarModeMap: [String: String]
}

private struct CalendarsListResult: Decodable {
    struct Calendar: Decodable { let id: String; let title: String; let colorHex: String? }
    let authorized: Bool
    let calendars: [Calendar]
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
    #expect(snapshot.stocks.tickers == ["SPY", "AAPL", "NVDA", "VTI"]) // the shipped starter list
}

@Test("a stocks-tickers patch round-trips through getSettings, normalized to uppercase and deduped")
func stocksTickersPatchRoundTrips() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    // Mixed case + a duplicate + surrounding whitespace: the store normalizes on write.
    let saved = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_stocks01","changes":{"stocks":{"tickers":["tsla","AAPL","tsla","brk.b"]}}}}"##
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)

    let reopened = try makeSessionWithSettings(paths)
    let response = await reopened.execute(operationRequest(.getSettings, "{}"))
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.stocks.tickers == ["TSLA", "AAPL", "BRK.B"]) // uppercased, order-preserving, deduped
}

@Test("a calendar→mode-map patch round-trips through getSettings; an invalid mode value is rejected (NIC-126)")
func calendarModeMapPatchRoundTrips() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let saved = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_calmap01","changes":{"calendarModeMap":{"cal-work":"executive","cal-dev":"developer"}}}}"##
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)

    let reopened = try makeSessionWithSettings(paths)
    let response = await reopened.execute(operationRequest(.getSettings, "{}"))
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.calendarModeMap == ["cal-work": "executive", "cal-dev": "developer"])

    // A value that is not a known mode id is rejected — settings can never invent a mode.
    let rejected = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_calmap02","changes":{"calendarModeMap":{"cal-x":"cosmic"}}}}"##
    ))
    #expect(try decode(rejected, as: Accepted.self).accepted == false)
}

@Test("listCalendars returns the host's calendars as authorized; a denied provider is unauthorized+empty (NIC-126)")
func listCalendarsReportsAuthorization() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        calendarProvider: MockCalendarProvider(events: [], calendars: [
            CalendarInfo(id: "cal-work", title: "Work", colorHex: "#3366cc"),
            CalendarInfo(id: "cal-personal", title: "Personal"),
        ])
    )
    let response = await session.execute(operationRequest(.listCalendars, "{}"))
    let result = try decode(response, as: CalendarsListResult.self)
    #expect(result.authorized)
    #expect(result.calendars.map(\.id) == ["cal-work", "cal-personal"])
    #expect(result.calendars.first?.colorHex == "#3366cc")

    // A denied grant → unauthorized + empty; the Settings UI shows a grant-access prompt.
    let denied = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        calendarProvider: MockCalendarProvider(error: .permissionDenied)
    )
    let deniedResponse = await denied.execute(operationRequest(.listCalendars, "{}"))
    let deniedResult = try decode(deniedResponse, as: CalendarsListResult.self)
    #expect(deniedResult.authorized == false)
    #expect(deniedResult.calendars.isEmpty)
}

@Test("an explicitly cleared ticker list stays empty rather than reverting to the starter list")
func stocksTickersClearedStaysEmpty() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = try makeSessionWithSettings(paths)
    let saved = await session.execute(operationRequest(
        .updateSettings,
        ##"{"patch":{"schemaVersion":"1.0.0","patchId":"set_stocks02","changes":{"stocks":{"tickers":[]}}}}"##
    ))
    #expect(try decode(saved, as: Accepted.self).accepted)

    let reopened = try makeSessionWithSettings(paths)
    let response = await reopened.execute(operationRequest(.getSettings, "{}"))
    let snapshot = try decode(response, as: SettingsSnapshot.self)
    #expect(snapshot.stocks.tickers.isEmpty) // cleared is a real state, not "unset"
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

// MARK: - listUrls / addUrlReference favicons (NIC-147)

/// Polls until `condition` holds or the timeout elapses — the favicon fetch runs in
/// a detached background task, so tests wait on the cache/emit rather than a return.
private func waitUntil(timeoutMs: Int = 3000, _ condition: @Sendable () -> Bool) async {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private func quickAppsChangedCount(_ emitted: EmittedEvents) -> Int {
    emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "mode.quickapps.changed" }.count
}

@Test("listUrls returns a cached favicon as base64 iconPng; uncached urls omit it")
func listUrlsReturnsCachedFavicon() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    // Warm the cache for the shipped github URL; leave docs cold. No capability, so
    // no background fetch runs — this isolates the read path.
    let seed = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
    FaviconCache(directory: paths.faviconCacheDirectory).store(png: seed, forTarget: "https://github.com")

    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory, workspace: paths
    )
    let response = await session.execute(operationRequest(.listUrls, "{}"))
    let urls = try decode(response, as: ListUrlsResult.self).urls

    let github = try #require(urls.first { $0.id == "github" })
    #expect(github.iconPng == seed.base64EncodedString())
    let docs = try #require(urls.first { $0.id == "docs" })
    #expect(docs.iconPng == nil)
}

@Test("listUrls warms cold favicons in the background, caches them, and emits a refresh")
func listUrlsWarmsFaviconsAndEmits() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let iconBytes = Data([0x89, 0x50, 0x4E, 0x47, 0xAA, 0xBB, 0xCC])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory, workspace: paths,
        faviconCapability: MockFaviconCapability(icon: iconBytes),
        emitEventJSON: { emitted.emit($0) }
    )

    // First read: cache is cold, so every url omits its icon and a warm pass starts.
    let first = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(first.urls.allSatisfy { $0.iconPng == nil })

    // The background fetch lands: the cache warms and a refresh event fires.
    let cache = FaviconCache(directory: paths.faviconCacheDirectory)
    await waitUntil { cache.icon(forTarget: "https://github.com") != nil }
    #expect(cache.icon(forTarget: "https://github.com") == iconBytes)
    await waitUntil { quickAppsChangedCount(emitted) >= 1 }
    #expect(quickAppsChangedCount(emitted) >= 1)

    // A subsequent read now carries the cached icon.
    let second = try decode(await session.execute(operationRequest(.listUrls, "{}")), as: ListUrlsResult.self)
    #expect(second.urls.first { $0.id == "github" }?.iconPng == iconBytes.base64EncodedString())
}

@Test("a failed favicon fetch records a miss and emits no refresh")
func failedFaviconRecordsMissNoEmit() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory, workspace: paths,
        faviconCapability: MockFaviconCapability(icon: nil), // every fetch fails
        emitEventJSON: { emitted.emit($0) }
    )
    _ = await session.execute(operationRequest(.listUrls, "{}"))

    let cache = FaviconCache(directory: paths.faviconCacheDirectory)
    // The miss is recorded (needsFetch becomes false), and no refresh event fires.
    await waitUntil { !cache.needsFetch(forTarget: "https://github.com") }
    #expect(!cache.needsFetch(forTarget: "https://github.com"))
    #expect(cache.icon(forTarget: "https://github.com") == nil)
    #expect(quickAppsChangedCount(emitted) == 0)
}

@Test("addUrlReference mints without an icon and warms the new url's favicon")
func addUrlReferenceWarmsFavicon() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let iconBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x10, 0x20])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory, workspace: paths,
        faviconCapability: MockFaviconCapability(icon: iconBytes)
    )
    let response = await session.execute(
        operationRequest(.addURLReference, #"{"url":"https://news.ycombinator.com","label":"Hacker News"}"#)
    )
    let payload = try decode(response, as: AddUrlResult.self)
    #expect(payload.accepted)
    // Minted cold: the tile shows its placeholder until the fetch lands.
    #expect(payload.reference?.iconPng == nil)

    let cache = FaviconCache(directory: paths.faviconCacheDirectory)
    await waitUntil { cache.icon(forTarget: "https://news.ycombinator.com") != nil }
    #expect(cache.icon(forTarget: "https://news.ycombinator.com") == iconBytes)
}

// MARK: - Collapse / expand all (NIC-143)

/// Records hide/unhide and serves a mutable visible-app set, so a test can exercise
/// the collapse-all bucket end to end (hiding removes from visible, un-hiding adds
/// back — mirroring `NSRunningApplication` app-level hide).
private final class CollapseWorkspaceWindows: WorkspaceWindowsCapability, @unchecked Sendable {
    private var visible: [String]
    private(set) var hidden: [String] = []
    private(set) var unhidden: [String] = []

    init(visible: [String]) { self.visible = visible }

    func visibleApplicationBundleIDs() async throws -> [String] { visible }
    func hideApplications(bundleIDs: [String]) async throws -> [String] {
        hidden.append(contentsOf: bundleIDs)
        visible.removeAll { bundleIDs.contains($0) }
        return bundleIDs
    }
    func unhideApplications(bundleIDs: [String]) async throws -> [String] {
        unhidden.append(contentsOf: bundleIDs)
        visible.append(contentsOf: bundleIDs)
        return bundleIDs
    }
}

private struct ToggleModeCollapseResult: Decodable { let collapsed: Bool }

private func windowCollapseEvents(_ emitted: EmittedEvents) -> [[String: Any]] {
    emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "mode.windowcollapse.changed" }
}

@Test("toggleModeCollapse hides the visible apps into the mode bucket, then un-hides exactly them")
func toggleModeCollapseRoundTrips() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let windows = CollapseWorkspaceWindows(visible: ["com.apple.Safari", "com.microsoft.VSCode"])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: windows,
        emitEventJSON: { emitted.emit($0) }
    )

    // Collapse: the two visible apps are hidden and the state flips to collapsed.
    let first = await session.execute(operationRequest(.toggleModeCollapse, #"{"modeId":"executive"}"#))
    #expect(try decode(first, as: ToggleModeCollapseResult.self).collapsed)
    #expect(windows.hidden == ["com.apple.Safari", "com.microsoft.VSCode"])
    let firstEvent = windowCollapseEvents(emitted).last?["payload"] as? [String: Any]
    #expect(firstEvent?["modeId"] as? String == "executive")
    #expect(firstEvent?["collapsed"] as? Bool == true)

    // Expand: exactly the bucket is un-hidden and the state flips back.
    let second = await session.execute(operationRequest(.toggleModeCollapse, #"{"modeId":"executive"}"#))
    #expect(try !decode(second, as: ToggleModeCollapseResult.self).collapsed)
    #expect(windows.unhidden == ["com.apple.Safari", "com.microsoft.VSCode"])
    #expect((windowCollapseEvents(emitted).last?["payload"] as? [String: Any])?["collapsed"] as? Bool == false)
}

@Test("collapsing with nothing visible is a no-op that stays expanded and emits nothing")
func toggleModeCollapseEmptyIsNoOp() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let windows = CollapseWorkspaceWindows(visible: [])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: windows,
        emitEventJSON: { emitted.emit($0) }
    )
    let response = await session.execute(operationRequest(.toggleModeCollapse, #"{"modeId":"executive"}"#))
    #expect(try !decode(response, as: ToggleModeCollapseResult.self).collapsed)
    #expect(windows.hidden.isEmpty)
    #expect(windowCollapseEvents(emitted).isEmpty)
}

@Test("a mode switch re-applies the entered mode's collapse bucket (bucket wins over restore)")
func modeSwitchReappliesCollapseBucket() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    let windows = CollapseWorkspaceWindows(visible: ["com.apple.Safari"])
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        workspace: paths,
        workspaceWindows: windows,
        emitEventJSON: { emitted.emit($0) }
    )
    // Collapse executive: Safari is now hidden and bucketed.
    _ = await session.execute(operationRequest(.toggleModeCollapse, #"{"modeId":"executive"}"#))
    // Simulate "Windows Stored by Mode" restore un-hiding Safari, then switch into
    // executive: the collapse bucket must re-hide it.
    _ = try await windows.unhideApplications(bundleIDs: ["com.apple.Safari"])
    let hiddenBefore = windows.hidden.count
    _ = await session.execute(operationRequest(.applyMode, #"{"modeId":"executive"}"#))

    #expect(windows.hidden.count > hiddenBefore)
    #expect((windowCollapseEvents(emitted).last?["payload"] as? [String: Any])?["collapsed"] as? Bool == true)
}

// MARK: - Close all windows (NIC-143)

@Test("closeAllWindows routes through the command bus and gates on a destructive confirmation")
func closeAllWindowsGatesOnConfirmation() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let emitted = EmittedEvents()
    // apps.quitall is macOS-only, so the runtime must be composed in the macOS phase
    // for the tool to resolve; `.mocks()` gives the (empty) lifecycle capability.
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths, phase: .macOS),
        configDirectory: paths.configDirectory,
        workspace: paths,
        emitEventJSON: { emitted.emit($0) }
    )
    let response = await session.execute(operationRequest(.closeAllWindows, "{}"))
    #expect(response.status == .ok)

    // A destructive tool never runs on the first call: the policy engine raises a
    // confirmation disclosure naming the quit tool, which the user must approve.
    let confirmations = emitted.all().compactMap { json -> [String: Any]? in
        try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }.filter { ($0["type"] as? String) == "confirmation.changed" }
    let disclosure = (confirmations.last?["payload"] as? [String: Any])?["confirmation"] as? [String: Any]
    #expect((disclosure?["tool"] as? [String: Any])?["id"] as? String == "apps.quitall")
    #expect(disclosure?["risk"] as? String == "destructive")
}

// MARK: - Window navigator (NIC-143)

private struct WindowInventoryResult: Decodable {
    struct Group: Decodable { let bundleId: String; let appName: String; let windows: [Window] }
    struct Window: Decodable { let id: String; let title: String; let minimized: Bool }
    let apps: [Group]
}
private struct WindowActionResult: Decodable { let ok: Bool }

@Test("listWindows returns the app-grouped inventory from the capability (NIC-143)")
func listWindowsReturnsInventory() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        appWindows: MockAppWindowsCapability()
    )
    let response = await session.execute(operationRequest(.listWindows, "{}"))
    let inventory = try decode(response, as: WindowInventoryResult.self)
    #expect(inventory.apps.map(\.bundleId) == ["com.google.Chrome", "com.microsoft.VSCode"])
    #expect(inventory.apps.first?.windows.map(\.id) == ["1001", "1002"])
    #expect(inventory.apps.first?.windows.last?.minimized == true)
}

@Test("window actions report whether they took effect, and no-op honestly without the capability")
func windowActionsReportEffect() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let windows = MockAppWindowsCapability()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        appWindows: windows
    )
    // A known id is acted on.
    let minimize = await session.execute(operationRequest(.minimizeWindow, #"{"windowId":"1001"}"#))
    #expect(try decode(minimize, as: WindowActionResult.self).ok)
    #expect(windows.minimized == ["1001"])
    // Close routes to the capability too.
    _ = await session.execute(operationRequest(.closeWindow, #"{"windowId":"2001"}"#))
    #expect(windows.closed == ["2001"])
    // An unknown id is a false result, never an error.
    let surface = await session.execute(operationRequest(.surfaceWindow, #"{"windowId":"9999"}"#))
    #expect(try !decode(surface, as: WindowActionResult.self).ok)

    // Without the capability (pre-Mac), the list is empty and actions no-op with ok:false.
    let bare = BridgeSession(runtime: try makeCommandRuntime(paths: paths), configDirectory: paths.configDirectory)
    #expect(try decode(await bare.execute(operationRequest(.listWindows, "{}")), as: WindowInventoryResult.self).apps.isEmpty)
    #expect(try !decode(
        await bare.execute(operationRequest(.minimizeWindow, #"{"windowId":"1001"}"#)),
        as: WindowActionResult.self
    ).ok)
}

// MARK: - Canvas connect/status (NIC-132)

private struct CanvasStatusDecode: Decodable {
    let available: Bool
    let endpoint: String
    let token: String?
    let lastScrapedAt: String?
    let courseCount: Int
    let deadlineCount: Int
}

@Test("getCanvasStatus reports the pairing endpoint/token and last-scrape summary")
func getCanvasStatusReportsPairing() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        canvasStatus: {
            CanvasStatusInfo(
                endpoint: "http://127.0.0.1:8899/canvas/ingest",
                token: "tok-123", lastScrapedAt: "2026-07-29T12:00:00Z",
                courseCount: 4, deadlineCount: 7
            )
        }
    )
    let response = await session.execute(operationRequest(.getCanvasStatus, "{}"))
    #expect(response.status == .ok)
    let status = try decode(response, as: CanvasStatusDecode.self)
    #expect(status.available)
    #expect(status.endpoint == "http://127.0.0.1:8899/canvas/ingest")
    #expect(status.token == "tok-123")
    #expect(status.lastScrapedAt == "2026-07-29T12:00:00Z")
    #expect(status.courseCount == 4)
    #expect(status.deadlineCount == 7)
}

@Test("getCanvasStatus reports unavailable off the macOS host (no ingest store)")
func getCanvasStatusUnavailableWithoutHost() async throws {
    let session = try makeSession() // no canvasStatus closure injected
    let response = await session.execute(operationRequest(.getCanvasStatus, "{}"))
    #expect(response.status == .ok)
    let status = try decode(response, as: CanvasStatusDecode.self)
    #expect(status.available == false)
    #expect(status.token == nil)
}

@Test("resetCanvas rotates the token and returns the fresh, empty state")
func resetCanvasReturnsFreshState() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        canvasReset: {
            CanvasStatusInfo(
                endpoint: "http://127.0.0.1:8899/canvas/ingest",
                token: "rotated-456", lastScrapedAt: nil, courseCount: 0, deadlineCount: 0
            )
        }
    )
    let response = await session.execute(operationRequest(.resetCanvas, "{}"))
    #expect(response.status == .ok)
    let status = try decode(response, as: CanvasStatusDecode.self)
    #expect(status.token == "rotated-456")
    #expect(status.lastScrapedAt == nil)
    #expect(status.courseCount == 0)
    #expect(status.deadlineCount == 0)
}
