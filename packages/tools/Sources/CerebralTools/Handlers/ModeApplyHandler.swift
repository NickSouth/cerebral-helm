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
        configVersion: String = ConfigValidator.schemaVersion,
        sessionSource: String = "command"
    ) {
        self.modeIDs = modeIDs
        self.coordinator = coordinator
        self.stateStore = stateStore
        self.settings = settings
        self.workspaceStore = workspaceStore
        self.windows = windows
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
                try workspaceStore.saveSnapshot(modeID: previous, bundleIDs: visible)
                let hidden = try await windows.hideApplications(bundleIDs: visible)
                actions.append(Action(
                    actionID: "store-windows",
                    kind: "workspace.hide",
                    message: "Stored and hid \(hidden.count) of \(visible.count) applications for '\(previous)'.",
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
                let returned = try await windows.unhideApplications(bundleIDs: stored)
                actions.append(Action(
                    actionID: "restore-windows",
                    kind: "workspace.restore",
                    message: "Returned \(returned.count) of \(stored.count) stored applications; quit applications are not relaunched.",
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
