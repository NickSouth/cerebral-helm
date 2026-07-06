import Foundation
import CerebralContracts
import CerebralCore

/// `mode.apply`: switch the active mode (workspace re-scope, NIC-85).
///
/// A mode switch persists the new active mode and records a mode session
/// (FR-MOD-05/06) while carrying the active context forward unchanged. It runs
/// **no workflow steps** — opening apps, URLs, and hooks belongs to explicitly
/// triggered quick-action workflows (the `run <action>` path).
///
/// When the single "Windows Stored by Mode" setting is on, the switch does at
/// most two window things, both best-effort and both reported honestly as
/// per-action results: it stores-and-hides the outgoing mode's visible
/// applications, and returns (un-hides) the incoming mode's stored, still-running
/// applications. Never launches anything; a window failure never fails the
/// switch — the result degrades to partial success (FR-MOD-04).
public struct ModeApplyHandler: ToolHandler {
    public let toolID = "mode.apply"
    private let modeIDs: Set<String>
    private let coordinator: ModeSessionCoordinator
    private let stateStore: any ModeStateStore
    private let settings: (any SettingsStore)?
    private let workspaceStore: any ModeWorkspaceStore
    private let windows: any WorkspaceWindowsCapability
    /// Geometry capture/restore (Accessibility). Best-effort enhancement: when
    /// untrusted or unavailable, snapshots store no frames and restore degrades
    /// to reactivation-only — surfaced in the action message, never a failure.
    private let windowFrames: any WindowCapability
    private let configVersion: String
    /// Recorded as the session's activation source (FR-MOD-06). The handler does
    /// not see the command envelope, so the composition supplies the surface
    /// (every current caller reaches here through the command bus).
    private let sessionSource: String

    public init(
        modeIDs: Set<String>,
        coordinator: ModeSessionCoordinator,
        stateStore: any ModeStateStore,
        settings: (any SettingsStore)? = nil,
        workspaceStore: any ModeWorkspaceStore = InMemoryModeWorkspaceStore(),
        windows: any WorkspaceWindowsCapability = MockWorkspaceWindowsCapability(matrix: .none),
        windowFrames: any WindowCapability = MockWindowCapability(matrix: .none),
        configVersion: String = ConfigValidator.schemaVersion,
        sessionSource: String = "command"
    ) {
        self.modeIDs = modeIDs
        self.coordinator = coordinator
        self.stateStore = stateStore
        self.settings = settings
        self.workspaceStore = workspaceStore
        self.windows = windows
        self.windowFrames = windowFrames
        self.configVersion = configVersion
        self.sessionSource = sessionSource
    }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmModeApplyInput
        do { decoded = try CerebralHelmModeApplyInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("mode.apply input does not match its contract.")
        }
        guard modeIDs.contains(decoded.modeID) else {
            throw ToolHandlerError.unavailable("Mode '\(decoded.modeID)' is not configured.")
        }

        let previousModeID = (try? stateStore.loadActiveModeID()) ?? nil
        let workspaceActions = await applyWindowBehavior(from: previousModeID, to: decoded.modeID)

        // Context is persisted separately from mode (FR-MOD-05): the switch
        // carries the current context forward, never clears it.
        let context = (try? stateStore.loadActiveContext()) ?? nil
        let allSucceeded = workspaceActions.allSatisfy { $0.status == .success }
        do {
            try coordinator.recordApplication(
                modeID: decoded.modeID,
                context: context,
                source: sessionSource,
                result: allSucceeded ? .success : .partialSuccess,
                configVersion: configVersion
            )
        } catch {
            throw ToolHandlerError.providerFailure("The mode switch could not be persisted.")
        }

        return try CerebralHelmModeApplyOutput(
            actions: workspaceActions,
            aggregateRisk: .localWrite,
            modeID: decoded.modeID,
            status: allSucceeded ? .success : .partialSuccess
        ).jsonData()
    }

    /// "Windows Stored by Mode": store-and-hide the outgoing mode's visible
    /// applications, then return the incoming mode's stored ones. Off (or a
    /// same-mode re-apply) does nothing; an unavailable capability reports one
    /// honest unavailable action instead of pretending.
    private func applyWindowBehavior(from previousModeID: String?, to modeID: String) async -> [Action] {
        let enabled = ((try? settings?.load())?.windowsStoredByMode) ?? false
        guard enabled, previousModeID != modeID else { return [] }

        var actions: [Action] = []

        if let previous = previousModeID {
            do {
                let visible = try await windows.visibleApplicationBundleIDs()
                // Geometry is captured before hiding (hidden windows may not
                // report frames) and is best-effort: an untrusted Accessibility
                // permission stores frame-less snapshots, surfaced in the message.
                let (snapshots, framesNote) = await captureFrames(for: visible)
                try workspaceStore.saveSnapshot(modeID: previous, apps: snapshots)
                let hidden = try await windows.hideApplications(bundleIDs: visible)
                actions.append(Action(
                    actionID: "store-windows",
                    kind: "workspace.hide",
                    message: "Stored and hid \(hidden.count) of \(visible.count) applications for '\(previous)'\(framesNote).",
                    risk: .localWrite,
                    status: .success
                ))
            } catch {
                actions.append(windowFailure(
                    actionID: "store-windows", kind: "workspace.hide", error: error
                ))
            }
        }

        do {
            let stored = (try workspaceStore.loadSnapshot(modeID: modeID)) ?? []
            if !stored.isEmpty {
                let returned = try await windows.unhideApplications(bundleIDs: stored.map(\.bundleID))
                let framesNote = await restoreFrames(for: stored, returned: Set(returned))
                actions.append(Action(
                    actionID: "restore-windows",
                    kind: "workspace.restore",
                    message: "Returned \(returned.count) of \(stored.count) stored applications\(framesNote); quit applications are not relaunched.",
                    risk: .localWrite,
                    status: .success
                ))
            }
        } catch {
            actions.append(windowFailure(
                actionID: "restore-windows", kind: "workspace.restore", error: error
            ))
        }

        return actions
    }

    /// Reads each visible application's main-window frame for the snapshot.
    /// Returns the snapshots plus a message note describing coverage; a missing
    /// Accessibility permission or capability yields frame-less snapshots and an
    /// honest note, never a failed switch.
    private func captureFrames(for bundleIDs: [String]) async -> ([WorkspaceAppSnapshot], String) {
        var snapshots: [WorkspaceAppSnapshot] = []
        var captured = 0
        var geometryUnavailable = false
        for bundleID in bundleIDs {
            do {
                let frame = try await windowFrames.captureFrame(bundleID: bundleID)
                if frame != nil { captured += 1 }
                snapshots.append(WorkspaceAppSnapshot(bundleID: bundleID, frame: frame))
            } catch {
                geometryUnavailable = true
                snapshots.append(WorkspaceAppSnapshot(bundleID: bundleID, frame: nil))
            }
        }
        if geometryUnavailable {
            return (snapshots, " (window positions not stored — needs the Accessibility permission)")
        }
        return (snapshots, captured > 0 ? " (positions stored for \(captured))" : "")
    }

    /// Reapplies stored frames to the applications that actually returned.
    /// Best-effort: per-app refusals and a missing permission degrade to
    /// reactivation-only with an honest note.
    private func restoreFrames(for stored: [WorkspaceAppSnapshot], returned: Set<String>) async -> String {
        let withFrames = stored.filter { $0.frame != nil && returned.contains($0.bundleID) }
        guard !withFrames.isEmpty else { return "" }
        var restored = 0
        for snapshot in withFrames {
            guard let frame = snapshot.frame else { continue }
            do {
                if case .arranged = try await windowFrames.restoreFrame(bundleID: snapshot.bundleID, rect: frame) {
                    restored += 1
                }
            } catch {
                return " (window positions not restored — needs the Accessibility permission)"
            }
        }
        return " (positions restored for \(restored) of \(withFrames.count))"
    }

    private func windowFailure(actionID: String, kind: String, error: Error) -> Action {
        if case NativeCapabilityError.unavailable = error {
            return Action(
                actionID: actionID,
                kind: kind,
                message: "Window storage is available on the macOS host.",
                risk: .localWrite,
                status: .unavailable
            )
        }
        return Action(
            actionID: actionID,
            kind: kind,
            message: "Window handling failed; the mode switch itself completed.",
            risk: .localWrite,
            status: .failed
        )
    }
}
