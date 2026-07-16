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

// MARK: - Per-window state ("each mode is its own laptop", NIC-143 follow-up)

private func win(_ id: String, _ bundle: String, _ title: String, minimized: Bool) -> ModeWindowState {
    ModeWindowState(windowID: id, bundleID: bundle, title: title, minimized: minimized)
}

@Test("reconcile brings each window to its remembered state, minimally")
func reconcileMatchesRememberedState() {
    let remembered = [
        win("1", "com.apple.Safari", "Inbox", minimized: false),   // want open
        win("2", "com.apple.Safari", "Docs", minimized: true),     // want minimized
        win("3", "com.apple.Notes", "Note", minimized: false),     // already correct
    ]
    let current = [
        win("1", "com.apple.Safari", "Inbox", minimized: true),    // minimized → surface
        win("2", "com.apple.Safari", "Docs", minimized: false),    // open → minimize
        win("3", "com.apple.Notes", "Note", minimized: false),     // matches → no-op
    ]
    #expect(ModeApplyHandler.reconcile(remembered: remembered, current: current) == [.surface("1"), .minimize("2")])
}

@Test("reconcile skips gone windows and matches a relaunched app by bundle + title")
func reconcileHandlesMissingAndRelaunch() {
    let remembered = [
        win("100", "com.apple.Safari", "Inbox", minimized: false),  // id changed after relaunch
        win("200", "com.apple.Mail", "Mailbox", minimized: false),  // window gone entirely
    ]
    let current = [win("999", "com.apple.Safari", "Inbox", minimized: true)]  // new id, same bundle+title
    #expect(ModeApplyHandler.reconcile(remembered: remembered, current: current) == [.surface("999")])
}

@Test("a window not in the mode's snapshot is minimized (doesn't belong to this mode)")
func reconcileMinimizesNonBelonging() {
    let remembered = [win("1", "com.apple.Safari", "Inbox", minimized: false)]  // this mode: Safari/Inbox open
    let current = [
        win("1", "com.apple.Safari", "Inbox", minimized: false),   // belongs, open → no-op
        win("2", "com.apple.Notes", "Scratch", minimized: false),  // opened in another mode → minimize
        win("3", "com.apple.Music", "Playlist", minimized: true),  // not here, already minimized → no-op
    ]
    #expect(ModeApplyHandler.reconcile(remembered: remembered, current: current) == [.minimize("2")])
}

@Test("an empty title never matches the snapshot, so an unknown open window is minimized")
func reconcileEmptyTitleIsNonBelonging() {
    let remembered = [win("1", "com.apple.Safari", "", minimized: false)]
    let current = [win("2", "com.apple.Safari", "", minimized: false)]  // empty title, different id → doesn't belong
    #expect(ModeApplyHandler.reconcile(remembered: remembered, current: current) == [.minimize("2")])
}

@Test("with no snapshot (a never-visited mode) every open window is minimized — a clean desktop")
func reconcileEmptyRememberedMinimizesAll() {
    let current = [
        win("1", "com.apple.Safari", "Inbox", minimized: false),
        win("2", "com.apple.Notes", "Scratch", minimized: true),  // already minimized → no-op
    ]
    #expect(ModeApplyHandler.reconcile(remembered: [], current: current) == [.minimize("1")])
}

/// A stateful ``AppWindowsCapability`` fake: `listWindows` reflects live state and
/// minimize/surface mutate it, so a mode round-trip can be asserted end to end.
private final class StatefulAppWindows: AppWindowsCapability, @unchecked Sendable {
    struct W { var id: String; var bundle: String; var title: String; var minimized: Bool }
    var windows: [W]
    private(set) var minimizeCalls: [String] = []
    private(set) var surfaceCalls: [String] = []
    init(_ windows: [W]) { self.windows = windows }

    func listWindows() async throws -> [AppWindowGroup] {
        Dictionary(grouping: windows, by: { $0.bundle }).map { bundle, ws in
            AppWindowGroup(bundleID: bundle, appName: bundle, windows: ws.map {
                AppWindowInfo(id: $0.id, title: $0.title, minimized: $0.minimized)
            })
        }
    }
    func minimize(windowID: String) async throws -> Bool {
        minimizeCalls.append(windowID)
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return false }
        windows[index].minimized = true
        return true
    }
    func surface(windowID: String) async throws -> Bool {
        surfaceCalls.append(windowID)
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return false }
        windows[index].minimized = false
        return true
    }
    func close(windowID: String) async throws -> Bool { false }
    func minimized(_ id: String) -> Bool? { windows.first { $0.id == id }?.minimized }
}

/// Poll until a condition holds (the deferred surface runs on a detached task).
private func waitUntil(_ condition: @Sendable () -> Bool) async {
    for _ in 0..<400 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@Test("each mode is its own laptop: a window's minimized state is remembered per mode (NIC-143 follow-up)")
func perModeWindowStateRoundTrips() async throws {
    let stateStore = InMemoryModeStateStore()
    let appWindows = StatefulAppWindows([
        .init(id: "1", bundle: "com.google.Chrome", title: "GitHub", minimized: false),
    ])
    let windowStates = InMemoryModeWindowStateStore()
    func apply(_ mode: String) async throws {
        let handler = ModeApplyHandler(
            modeIDs: ["executive", "developer"],
            coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: InMemoryModeSessionLog()),
            stateStore: stateStore,
            settings: FixedSettings(stored: StoredSettings(windowsStoredByMode: true)),
            windows: MockWorkspaceWindowsCapability(matrix: .allAvailable),
            appWindows: appWindows,
            windowStates: windowStates,
            // Near-zero so the deferred un-minimize runs promptly in the test; production
            // holds it for the mode-swap wave (600ms).
            surfaceDelay: .milliseconds(1)
        )
        _ = try await handler.execute(input: Data(#"{"modeId":"\#(mode)"}"#.utf8))
    }

    // Land in executive; minimize the window there, then switch to developer.
    try await apply("executive")
    appWindows.windows[0].minimized = true
    try await apply("developer")
    // Open it in developer, then switch back to executive.
    appWindows.windows[0].minimized = false
    try await apply("executive")
    // Executive remembered it minimized → it is minimized again on return (minimize is
    // synchronous, part of the clear).
    #expect(appWindows.minimized("1") == true)
    #expect(appWindows.minimizeCalls.contains("1"))

    // Back to developer → it opens again (developer remembered it open). The un-minimize is
    // deferred past the mode-swap wave, so wait for the detached restore.
    try await apply("developer")
    await waitUntil { appWindows.minimized("1") == false }
    #expect(appWindows.minimized("1") == false)
    #expect(appWindows.surfaceCalls.contains("1"))
}
