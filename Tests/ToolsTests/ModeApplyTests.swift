import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// `mode.apply` after the workspace re-scope (NIC-85): a mode switch persists the
/// active mode and records a session (FR-MOD-05/06) and runs **no** workflow
/// steps — opening apps/URLs/hooks belongs to explicitly triggered quick actions.

private func makeHandler(
    stateStore: InMemoryModeStateStore = InMemoryModeStateStore(),
    sessionLog: InMemoryModeSessionLog = InMemoryModeSessionLog()
) -> ModeApplyHandler {
    ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: sessionLog),
        stateStore: stateStore
    )
}

@Test("mode.apply persists the active mode and records a session (FR-MOD-05/06)")
func modeApplyPersistsAndRecords() async throws {
    let stateStore = InMemoryModeStateStore()
    let sessionLog = InMemoryModeSessionLog()
    let handler = makeHandler(stateStore: stateStore, sessionLog: sessionLog)

    let output = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.modeID == "developer")
    #expect(decoded.status == .success)
    #expect(decoded.aggregateRisk == .localWrite)
    // No workflow steps run on a mode switch.
    #expect(decoded.actions.isEmpty)

    #expect(try stateStore.loadActiveModeID() == "developer")
    let sessions = try sessionLog.read()
    #expect(sessions.count == 1)
    #expect(sessions.first?.modeID == "developer")
    #expect(sessions.first?.result == .success)
}

@Test("mode.apply carries the active context forward unchanged (FR-MOD-05)")
func modeApplyPreservesContext() async throws {
    let stateStore = InMemoryModeStateStore()
    let sessionLog = InMemoryModeSessionLog()
    try stateStore.saveActiveContext(ProjectContext(id: "cerebralhelm", label: "CerebralHelm"))
    let handler = makeHandler(stateStore: stateStore, sessionLog: sessionLog)

    _ = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))

    #expect(try stateStore.loadActiveContext()?.id == "cerebralhelm")
    #expect(try sessionLog.read().first?.context?.id == "cerebralhelm")
}

// MARK: - Windows Stored by Mode (NIC-85)

private struct FixedSettings: SettingsStore {
    let stored: StoredSettings
    func load() throws -> StoredSettings { stored }
    func apply(_ changes: SettingsChanges) throws {}
}

@Test("with the toggle on, a switch stores-and-hides the outgoing mode and returns the incoming one")
func windowsStoredByModeStoresHidesAndRestores() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let workspaceStore = InMemoryModeWorkspaceStore()
    // Executive's earlier departure stored Safari and Mail; Mail has since quit.
    try workspaceStore.saveSnapshot(modeID: "executive", apps: [
        WorkspaceAppSnapshot(bundleID: "com.apple.Safari"),
        WorkspaceAppSnapshot(bundleID: "com.apple.Mail"),
    ])
    let handler = ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
        workspaceStore: workspaceStore,
        windows: MockWorkspaceWindowsCapability(
            visibleBundleIDs: ["com.microsoft.VSCode", "com.apple.Terminal"],
            runningBundleIDs: ["com.apple.Safari"]
        )
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.status == .success)

    // The outgoing developer workspace was stored…
    #expect(try workspaceStore.loadSnapshot(modeID: "developer")?.map(\.bundleID) == ["com.microsoft.VSCode", "com.apple.Terminal"])
    // …and both window operations report honestly, including the quit app.
    let byID = Dictionary(uniqueKeysWithValues: decoded.actions.map { ($0.actionID, $0) })
    #expect(byID["store-windows"]?.status == .success)
    #expect(byID["restore-windows"]?.status == .success)
    #expect(byID["restore-windows"]?.message?.contains("1 of 2") == true)
}

@Test("window frames are captured on departure and restored on return (NIC-85 geometry)")
func windowGeometryCapturesAndRestores() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let workspaceStore = InMemoryModeWorkspaceStore()
    // Executive stored Safari with a frame last time it was left.
    try workspaceStore.saveSnapshot(modeID: "executive", apps: [
        WorkspaceAppSnapshot(bundleID: "com.apple.Safari", frame: WindowRect(x: 5, y: 30, width: 900, height: 700)),
    ])
    let handler = ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
        workspaceStore: workspaceStore,
        windows: MockWorkspaceWindowsCapability(
            visibleBundleIDs: ["com.microsoft.VSCode"],
            runningBundleIDs: ["com.apple.Safari"]
        ),
        windowFrames: MockWindowCapability(
            arrangeOutcomes: ["com.apple.Safari": .arranged],
            capturedFrames: ["com.microsoft.VSCode": WindowRect(x: 0, y: 25, width: 800, height: 775)]
        )
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.status == .success)

    // Departure captured VS Code's frame into the developer snapshot…
    let stored = try workspaceStore.loadSnapshot(modeID: "developer")
    #expect(stored?.first?.frame == WindowRect(x: 0, y: 25, width: 800, height: 775))
    // …and both messages surface geometry coverage honestly.
    let byID = Dictionary(uniqueKeysWithValues: decoded.actions.map { ($0.actionID, $0) })
    #expect(byID["store-windows"]?.message?.contains("positions stored for 1") == true)
    #expect(byID["restore-windows"]?.message?.contains("positions restored for 1 of 1") == true)
}

@Test("without Accessibility, restore degrades to reactivation-only with an honest note")
func windowGeometryDegradesWithoutAccessibility() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let workspaceStore = InMemoryModeWorkspaceStore()
    try workspaceStore.saveSnapshot(modeID: "executive", apps: [
        WorkspaceAppSnapshot(bundleID: "com.apple.Safari", frame: WindowRect(x: 5, y: 30, width: 900, height: 700)),
    ])
    let handler = ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
        workspaceStore: workspaceStore,
        windows: MockWorkspaceWindowsCapability(
            visibleBundleIDs: ["com.microsoft.VSCode"],
            runningBundleIDs: ["com.apple.Safari"]
        ),
        // Accessibility denied: geometry is unavailable, hide/return still work.
        windowFrames: MockWindowCapability(fault: .permissionDenied)
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    // The core hide/return behavior succeeded; geometry is a surfaced degradation.
    #expect(decoded.status == .success)
    let byID = Dictionary(uniqueKeysWithValues: decoded.actions.map { ($0.actionID, $0) })
    #expect(byID["store-windows"]?.message?.contains("Accessibility") == true)
    #expect(byID["restore-windows"]?.message?.contains("Accessibility") == true)
    // The snapshot still stored the apps, frame-less.
    #expect(try workspaceStore.loadSnapshot(modeID: "developer")?.first
        == WorkspaceAppSnapshot(bundleID: "com.microsoft.VSCode", frame: nil))
}

@Test("with the toggle off, a switch performs no window operations")
func windowsToggleOffDoesNothing() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let workspaceStore = InMemoryModeWorkspaceStore()
    let handler = ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: false)),
        workspaceStore: workspaceStore,
        windows: MockWorkspaceWindowsCapability(visibleBundleIDs: ["com.microsoft.VSCode"])
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.status == .success)
    #expect(decoded.actions.isEmpty)
    #expect(try workspaceStore.loadSnapshot(modeID: "developer") == nil)
}

@Test("toggle on without the native capability degrades to partial success, and the switch still lands")
func windowsToggleUnavailableDegradesHonestly() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let handler = ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
        workspaceStore: InMemoryModeWorkspaceStore(),
        windows: MockWorkspaceWindowsCapability(matrix: .none)
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.status == .partialSuccess)
    #expect(decoded.actions.contains { $0.status == .unavailable })
    // The switch itself still persisted.
    #expect(try stateStore.loadActiveModeID() == "executive")
}

@Test("re-applying the active mode never hides or restores anything")
func sameModeSwitchSkipsWindowBehavior() async throws {
    let stateStore = InMemoryModeStateStore()
    try stateStore.saveActiveModeID("developer")
    let workspaceStore = InMemoryModeWorkspaceStore()
    let handler = ModeApplyHandler(
        modeIDs: ["developer"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
        stateStore: stateStore,
        settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
        workspaceStore: workspaceStore,
        windows: MockWorkspaceWindowsCapability(visibleBundleIDs: ["com.microsoft.VSCode"])
    )

    let output = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.actions.isEmpty)
    #expect(try workspaceStore.loadSnapshot(modeID: "developer") == nil)
}

@Test("mode.apply reports an unconfigured mode as unavailable")
func modeApplyRejectsUnknownMode() async throws {
    let handler = makeHandler()

    do {
        _ = try await handler.execute(input: Data(#"{"modeId":"nonexistent"}"#.utf8))
        Issue.record("An unconfigured mode must not succeed.")
    } catch let error as ToolHandlerError {
        guard case .unavailable = error else {
            Issue.record("Expected unavailable, got \(error)")
            return
        }
    }
}

@Test("a persistence failure is a provider failure, not a silent success")
func modeApplyReportsPersistenceFailure() async throws {
    struct FailingLog: ModeSessionLog {
        func append(_ session: ModeSession) throws { throw CocoaError(.fileWriteUnknown) }
        func read() throws -> [ModeSession] { [] }
    }
    let stateStore = InMemoryModeStateStore()
    let handler = ModeApplyHandler(
        modeIDs: ["developer"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: FailingLog()),
        stateStore: stateStore
    )

    do {
        _ = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
        Issue.record("A failed persistence must not report success.")
    } catch let error as ToolHandlerError {
        guard case .providerFailure = error else {
            Issue.record("Expected providerFailure, got \(error)")
            return
        }
    }
}
