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
    /// Per-window enumeration + minimize/surface for the "each mode is its own laptop"
    /// state layer (NIC-143 follow-up). Best-effort: an untrusted/absent capability
    /// simply captures and applies nothing.
    private let appWindows: any AppWindowsCapability
    /// Session-only, per-mode remembered window states (open vs minimized). Never
    /// persisted; layered on top of the durable app-level ``ModeWorkspaceStore``.
    private let windowStates: any ModeWindowStateStore
    /// How long to hold the un-minimize (`surface`) of an entered mode's windows so the
    /// mode-swap wave plays over the cleared dashboard first, then windows return (owner
    /// sequencing). Matches the web wave duration (600ms); the minimize half stays
    /// synchronous with the clear. Injectable so tests don't wait.
    private let surfaceDelay: Duration
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
        appWindows: any AppWindowsCapability = MockAppWindowsCapability(groups: []),
        windowStates: any ModeWindowStateStore = InMemoryModeWindowStateStore(),
        surfaceDelay: Duration = .milliseconds(600),
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
        self.appWindows = appWindows
        self.windowStates = windowStates
        self.surfaceDelay = surfaceDelay
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

        // "Each mode is its own laptop" (NIC-143 follow-up): remember the outgoing mode's
        // per-window open/minimized state before anything hides, so it can be re-applied
        // on return. Best-effort and silent — a refinement of the app-level store/restore
        // below, never its own action or a failure.
        if let previous = previousModeID {
            await captureWindowStates(modeID: previous)
        }

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

        // Re-apply the incoming mode's remembered per-window state, after its apps are
        // un-hidden — minimize the windows that were minimized in this mode, surface the
        // ones that were open. Best-effort and silent.
        await applyWindowStates(modeID: modeID)

        return actions
    }

    // MARK: - Per-window state ("each mode is its own laptop")

    /// One reconcile step: bring a window to its remembered state.
    public enum WindowReconcile: Equatable, Sendable {
        case minimize(String)
        case surface(String)
    }

    /// The minimal set of minimize/surface actions to bring the desktop to the state the
    /// entered mode should show. Iterates the *live* windows: a window that **belongs** to
    /// the mode (present in its snapshot, matched by stable id or bundle + non-empty title
    /// after a relaunch) takes its remembered minimized state; a window that does **not**
    /// belong is minimized — it was never opened or surfaced in this mode, so "each mode is
    /// its own laptop" keeps it off this mode's desktop. A window already in the wanted state
    /// yields no action; a closed/quit window is simply absent (not reopened, out of scope).
    /// Pure and exposed for tests.
    public static func reconcile(remembered: [ModeWindowState], current: [ModeWindowState]) -> [WindowReconcile] {
        let rememberedByID = Dictionary(remembered.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var actions: [WindowReconcile] = []
        for live in current {
            let belongs = rememberedByID[live.windowID]
                ?? remembered.first { $0.bundleID == live.bundleID && !$0.title.isEmpty && $0.title == live.title }
            // Belongs → its remembered state; doesn't belong → minimized (not this mode's window).
            let wantMinimized = belongs?.minimized ?? true
            guard live.minimized != wantMinimized else { continue }
            actions.append(wantMinimized ? .minimize(live.windowID) : .surface(live.windowID))
        }
        return actions
    }

    /// Snapshot every currently-open window's state for a mode (before its apps hide).
    private func captureWindowStates(modeID: String) async {
        guard let states = try? await listWindowStates() else { return }
        windowStates.save(modeID: modeID, windows: states)
    }

    /// Re-apply a mode's remembered window states against the live windows, sequenced
    /// around the mode-swap animation (owner sequencing): minimize now — part of clearing
    /// the outgoing layout before the wave — and hold the un-minimize (`surface`) until the
    /// wave has played over the cleared dashboard, so windows return after it rather than
    /// during it. The deferred surface re-checks the active mode, so a rapid re-switch
    /// within the delay never surfaces a stale mode's windows.
    private func applyWindowStates(modeID: String) async {
        // No snapshot (a never-visited mode) still reconciles: with nothing remembered,
        // every open window is "not this mode's" and gets minimized — a clean desktop.
        let remembered = windowStates.load(modeID: modeID) ?? []
        guard let current = try? await listWindowStates() else { return }
        let actions = Self.reconcile(remembered: remembered, current: current)

        var surfaces: [String] = []
        for action in actions {
            switch action {
            case let .minimize(id): _ = try? await appWindows.minimize(windowID: id)
            case let .surface(id): surfaces.append(id)
            }
        }
        guard !surfaces.isEmpty else { return }

        // Capture only Sendable values (never `self`) for the detached, fire-and-forget
        // restore — the mode switch's response returns immediately; windows come back after.
        let capability = appWindows
        let stateStore = self.stateStore
        let delay = surfaceDelay
        let target = modeID
        Task {
            try? await Task.sleep(for: delay)
            guard (try? stateStore.loadActiveModeID()) == target else { return }  // switched again — stale
            for id in surfaces {
                _ = try? await capability.surface(windowID: id)
            }
        }
    }

    /// Flatten the per-app window inventory into per-window states.
    private func listWindowStates() async throws -> [ModeWindowState] {
        try await appWindows.listWindows().flatMap { group in
            group.windows.map {
                ModeWindowState(windowID: $0.id, bundleID: group.bundleID, title: $0.title, minimized: $0.minimized)
            }
        }
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
