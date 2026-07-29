import Foundation
import CerebralContracts
import CerebralCore
import CerebralTools

/// The outcome of a successful Spotify connect (NIC-133), returned by the host's connect closure to
/// the `connectSpotify` op: the granted scope only. The OAuth tokens are persisted to the Keychain
/// by the Mac coordinator and never travel back through the bridge.
public struct SpotifyConnectionInfo: Sendable, Equatable {
    public let scope: String?
    public init(scope: String?) {
        self.scope = scope
    }
}

/// Executes versioned bridge operation requests against the live ``CommandRuntime``
/// (NIC-74b, ADR-004). Transport-agnostic: the WKWebView transport (or a test) hands
/// it a decoded operation request and forwards the response it returns.
///
/// This increment maps the command-style operations — `submitCommand` and
/// `applyMode` — onto `CommandRuntime.submit`. The structured knowledge/confirmation/
/// settings operations, `getBootstrapState`, `getRecentActivity`, and the event
/// stream land in following increments; until then they return a structured
/// `unavailable_capability` error so the dashboard degrades honestly rather than
/// hanging on a missing reply.
public final class BridgeSession: @unchecked Sendable {
    private let runtime: CommandRuntime
    private let configDirectory: URL
    /// The full workspace, when the host has one (the shell). Enables the
    /// user-overrides read side (bootstrap composes through `ConfigLoader`, so
    /// pinned quick apps appear — NIC-119c) and the validated override write
    /// path. nil = shipped-defaults composition (tests, workspace-less hosts).
    private let workspace: WorkspacePaths?
    /// Durable settings persistence (FR-CFG-04). Optional so a host without a
    /// database binding (some tests) still validates patches; when absent, an
    /// accepted patch is validated but not saved — the pre-store behavior.
    private let settingsStore: (any SettingsStore)?
    /// The durable active-mode store (FR-MOD-05). When bound, bootstrap restores
    /// the last active mode; when absent, the stored default applies.
    private let modeStateStore: (any ModeStateStore)?
    /// The composed capability flags the handshake reports (FR-SHL-06), derived at
    /// composition time from the bound capability bundle, phase, and platform
    /// permissions (``CompositionCapabilities``). Defaults to the honest pre-Mac
    /// mock set: every native capability unavailable. Mutable because permission
    /// state can change while running (NIC-83) — the shell rechecks on activation
    /// and updates via ``updateCapabilities(_:)``.
    public var capabilities: [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return currentCapabilities
    }

    private let capabilitiesLock = NSLock()
    private var currentCapabilities: [CerebralContracts.Capability]
    private let messageSchemaVersion = "1.0.0"
    /// Emits an already-encoded bridge-event JSON string to the dashboard (Sendable
    /// String — no non-Sendable DTO crosses the transport boundary).
    private let emitEventJSON: @Sendable (String) -> Void

    /// Pending confirmations awaiting a decision, keyed by disclosure id
    /// (== `ConfirmationToken.confirmationID`). The token is a single-use secret held
    /// only here; the dashboard decides by id and never sees the token.
    private let tokenLock = NSLock()
    private var pendingTokens: [String: ConfirmationToken] = [:]

    /// Fetches site favicons for URL quick apps (NIC-147). Optional: a host without
    /// it (tests, workspace-less hosts) simply serves URL tiles without favicons.
    /// The fetch runs in the background off `listUrls`/`addUrlReference`; results are
    /// cached under the state root and pushed live via `mode.quickapps.changed`.
    private let faviconCapability: (any FaviconCapability)?
    /// Origins with an in-flight favicon fetch, so overlapping `listUrls` calls never
    /// crawl the same site twice concurrently.
    private let faviconLock = NSLock()
    private var faviconInFlightOrigins: Set<String> = []

    /// Enumerates the user's Chrome profiles for the profile dropdown and avatar
    /// badges (NIC-151). Optional: a host without it (tests, non-Mac) serves an
    /// empty profile list, so the UI simply offers no profile choices.
    private let chromeProfiles: (any ChromeProfileDiscoveryCapability)?
    /// Lists the user's calendars for the Settings calendar→mode mapping (NIC-126). Optional: a
    /// host without it (tests, non-Mac) serves an unauthorized/empty list, so the UI shows its
    /// honest "grant Calendar access" state.
    private let calendarProvider: (any CalendarProvider)?
    /// Provisions and answers presence for logical secret references (NIC-134): the
    /// `storeSecret`/`getSecretStatus` ops drive it directly, like `secretStore` on the Mac
    /// composition. Optional — a host without it (tests without secrets, pre-Mac) reports the
    /// secret surface honestly unavailable. The stored *value* never leaves this session: it is
    /// written through `store` and its presence read through `resolve`; the response never
    /// echoes it (FR-CFG-03, FR-OBS-03).
    private let secretStore: (any SecretManaging)?
    /// Invoked with the reference after a secret is successfully stored (NIC-134), so a live
    /// consumer — e.g. the releases producer keyed on the TMDB API key — can refresh at once
    /// rather than waiting out its slow cadence. Optional; a host without live secret consumers
    /// leaves it nil.
    private let onSecretStored: (@Sendable (String) -> Void)?

    /// Invoked after a settings patch is durably applied, carrying the applied changes, so a
    /// host can refresh a live producer that depends on a setting (e.g. the Stocks producer
    /// re-samples when the ticker list changes, NIC-128) instead of waiting out its slow
    /// cadence. Optional; a host with no settings-driven producers leaves it nil.
    private let onSettingsChanged: (@Sendable (SettingsChanges) -> Void)?

    /// Runs the Spotify OAuth connect flow (NIC-133): the `connectSpotify` op awaits it, and it
    /// resolves once the browser round trip completes (tokens are persisted to the Keychain by the
    /// coordinator) or throws honestly (no Client ID, user cancelled, Spotify rejected). Optional —
    /// a host without the Mac coordinator (pre-Mac, tests) reports the connect surface unavailable.
    /// The tokens never cross back through here; only the granted scope does.
    private let spotifyConnect: (@Sendable () async throws -> SpotifyConnectionInfo)?

    /// Hides a layout's app windows on `closeLayout` (NIC-142) — the same
    /// permission-free `NSRunningApplication` primitive "Windows Stored by Mode"
    /// uses. Optional: a host without it (pre-Mac, tests) still ends the session
    /// and clears the bar, but cannot hide the windows (honestly degraded).
    private let workspaceWindows: (any WorkspaceWindowsCapability)?

    /// Surfaces a layout quick-toggle target on `toggleLayout` (NIC-142): the same
    /// app/URL open capabilities the runtime uses, called directly. The layout
    /// session is authorized once at open, so a rapid toggle does not re-confirm
    /// (owner decision) — these bypass the confirmation gate the way `closeLayout`'s
    /// hide does, never a per-press prompt. The shared URL capability reuses the
    /// runtime's tab-surfacing registry, so toggling to a URL surfaces its tab.
    private let app: (any AppCapability)?
    private let url: (any URLCapability)?

    /// Reads visible windows' frames for live layout capture (NIC-142) — the AX
    /// geometry capability. Optional: absent pre-Mac, so capture degrades honestly.
    private let window: (any WindowCapability)?

    /// Enumerates and acts on individual open windows for the window navigator
    /// (NIC-143): list, minimize, surface, close. Direct-capability like the layout
    /// ops — navigator actions are authorized as benign local view changes, never a
    /// per-press confirmation. Optional: absent pre-Mac/tests, so the navigator
    /// degrades to an honest empty inventory and no-op actions. The live AX adapter
    /// lands in a later increment.
    private let appWindows: (any AppWindowsCapability)?
    /// Resolves the default browser's bundle id (NIC-142) so a layout URL window that
    /// opens in the default browser (no Chrome profile) can be arranged like an app.
    /// A URL with a Chrome profile always targets `com.google.Chrome`.
    private let defaultBrowserBundleID: (@Sendable () -> String?)?

    /// The active layout session (NIC-142), when a layout is open. Ephemeral
    /// runtime state — started by `openLayout`, cleared by `closeLayout` or a mode
    /// switch. Guarded by its own lock; the session is the only source of the
    /// `layout.session.changed` state.
    private let layoutLock = NSLock()
    private var activeLayoutSession: LayoutSession?

    /// The session-only, per-mode collapse-all buckets (NIC-143). In-memory and not
    /// persisted — a relaunch starts every mode expanded. Owned wholly by the bridge:
    /// the toggle op fills/empties it, and a mode switch re-applies the entered mode's
    /// bucket after any "Windows Stored by Mode" restore (the bucket wins).
    private let collapseStore = ModeCollapseStore()

    public init(
        runtime: CommandRuntime,
        configDirectory: URL,
        workspace: WorkspacePaths? = nil,
        capabilities: [CerebralContracts.Capability] = CompositionCapabilities.bridgeCapabilities(phase: .preMac, nativeCapabilityIDs: []),
        settingsStore: (any SettingsStore)? = nil,
        modeStateStore: (any ModeStateStore)? = nil,
        faviconCapability: (any FaviconCapability)? = nil,
        chromeProfiles: (any ChromeProfileDiscoveryCapability)? = nil,
        calendarProvider: (any CalendarProvider)? = nil,
        secretStore: (any SecretManaging)? = nil,
        onSecretStored: (@Sendable (String) -> Void)? = nil,
        onSettingsChanged: (@Sendable (SettingsChanges) -> Void)? = nil,
        spotifyConnect: (@Sendable () async throws -> SpotifyConnectionInfo)? = nil,
        workspaceWindows: (any WorkspaceWindowsCapability)? = nil,
        app: (any AppCapability)? = nil,
        url: (any URLCapability)? = nil,
        window: (any WindowCapability)? = nil,
        appWindows: (any AppWindowsCapability)? = nil,
        defaultBrowserBundleID: (@Sendable () -> String?)? = nil,
        emitEventJSON: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.configDirectory = configDirectory
        self.workspace = workspace
        self.settingsStore = settingsStore
        self.modeStateStore = modeStateStore
        self.faviconCapability = faviconCapability
        self.chromeProfiles = chromeProfiles
        self.calendarProvider = calendarProvider
        self.secretStore = secretStore
        self.onSecretStored = onSecretStored
        self.onSettingsChanged = onSettingsChanged
        self.spotifyConnect = spotifyConnect
        self.workspaceWindows = workspaceWindows
        self.app = app
        self.url = url
        self.window = window
        self.appWindows = appWindows
        self.defaultBrowserBundleID = defaultBrowserBundleID
        self.currentCapabilities = capabilities
        self.emitEventJSON = emitEventJSON
    }

    /// The one composition every snapshot/bootstrap emission uses: through the
    /// layered loader (user overrides included) when a workspace is bound, else
    /// the shipped defaults.
    private func composeState(activeModeID: String?) -> CerebralHelmBridgeBootstrapState {
        // When the live-metrics provider is available a sample is inbound, so the composed
        // System Health region loads (`.empty`) rather than reporting unavailable — the shell
        // shows a same-shape skeleton instead of an "unavailable" flash on first paint or a
        // mode switch (NIC-136). Absent the provider it stays honestly unavailable.
        let metricsExpected = capabilities.first { $0.id == "system.metrics" }?.available == true
        if let workspace {
            return BootstrapComposer.compose(
                workspace: workspace, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
            )
        }
        return BootstrapComposer.compose(
            configDirectory: configDirectory, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
        )
    }

    /// Replaces the reported capability set (a permission recheck, NIC-83) and
    /// returns the capabilities whose availability changed, so the caller can
    /// emit one `bridge.capability.changed` event per transition. Future
    /// handshakes report the updated set.
    public func updateCapabilities(
        _ updated: [CerebralContracts.Capability]
    ) -> [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        let previousByID = Dictionary(uniqueKeysWithValues: currentCapabilities.map { ($0.id, $0) })
        currentCapabilities = updated
        return updated.filter { capability in
            previousByID[capability.id]?.available != capability.available
        }
    }

    public func execute(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        switch request.operation {
        case .getBootstrapState:
            return ok(request, payload: composeBootstrapState())
        case .submitCommand:
            return await submitCommand(request)
        case .applyMode:
            return await applyMode(request)
        case .captureNote:
            return await captureNote(request)
        case .searchNotes:
            return await searchNotes(request)
        case .getRecentActivity:
            return getRecentActivity(request)
        case .decideConfirmation:
            return await decideConfirmation(request)
        case .updateSettings:
            return updateSettings(request)
        case .listApps:
            return await listApps(request)
        case .updateQuickApps:
            return updateQuickApps(request)
        case .addURLReference:
            return addUrlReference(request)
        case .listUrls:
            return listUrls(request)
        case .listChromeProfiles:
            return await listChromeProfiles(request)
        case .addChromeProfileReference:
            return addChromeProfileReference(request)
        case .runSpeedTest:
            return await runSpeedTest(request)
        case .getSettings:
            return getSettings(request)
        case .storeSecret:
            return await storeSecret(request)
        case .getSecretStatus:
            return await getSecretStatus(request)
        case .deleteSecret:
            return await deleteSecret(request)
        case .connectSpotify:
            return await connectSpotify(request)
        case .openLayout:
            return await openLayout(request)
        case .closeLayout:
            return await closeLayout(request)
        case .toggleLayout:
            return await toggleLayout(request)
        case .pinLayoutWindow:
            return await pinLayoutWindow(request)
        case .updateLayout:
            return await updateLayout(request)
        case .captureLayout:
            return await captureLayout(request)
        case .addLayoutTarget:
            return await addLayoutTarget(request)
        case .toggleModeCollapse:
            return await toggleModeCollapse(request)
        case .closeAllWindows:
            return await closeAllWindows(request)
        case .listWindows:
            return await listWindows(request)
        case .listCalendars:
            return await listCalendars(request)
        case .minimizeWindow:
            return await windowAction(request) { try await $0.minimize(windowID: $1) }
        case .surfaceWindow:
            return await windowAction(request) { try await $0.surface(windowID: $1) }
        case .closeWindow:
            return await windowAction(request) { try await $0.close(windowID: $1) }
        default:
            // captureNote (confirmation-gated local_write returning a synchronous
            // noteId) and subscribe follow later.
            return unimplemented(request)
        }
    }

    // MARK: - Operations

    private func submitCommand(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SubmitCommandInput = decodePayload(request), !input.rawInput.isEmpty else {
            return invalidInput(request, "submitCommand requires a non-empty rawInput.")
        }
        // Honor an explicit, known source; default to `dashboard`. This keeps the
        // command bus honest about provenance (FR-CMD-01) without trusting arbitrary
        // strings.
        let source = input.source.flatMap(CommandSource.init(rawValue:)) ?? .dashboard
        let outcome = await runtime.submit(input.rawInput, source: source)
        registerAwaitingConfirmation(outcome)
        await emitConfigChangedIfModeApplied(outcome)
        return ok(request, payload: receipt(for: outcome))
    }

    /// A raw `mode <id>` command (palette, CLI-over-bridge) that succeeded also
    /// re-themes the dashboard, exactly like the `applyMode` operation — one
    /// switch, one visible result, regardless of which surface asked.
    private func emitConfigChangedIfModeApplied(_ outcome: CommandRuntimeOutcome) async {
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let result, result.toolID == "mode.apply",
            let output = result.output,
            let decoded = try? CerebralHelmModeApplyOutput(data: output)
        else { return }
        // A mode switch ends any active layout session — the outgoing layout's
        // windows fall under the mode's own snapshot behavior (NIC-142).
        endActiveLayoutSession()
        let snapshot = composeState(activeModeID: decoded.modeID)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        await reapplyCollapseBucket(enteredModeID: decoded.modeID)
    }

    private func applyMode(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ApplyModeInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "applyMode requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "error"))
        }
        // A mode switch is a real command: `mode.apply` persists the active mode
        // and records a session (FR-MOD-05/06). It runs no workflow steps — the
        // dashboard swap below and the durable switch are the whole effect
        // (workspace re-scope, NIC-85).
        _ = await runtime.submit("mode \(input.modeId)", source: .dashboard)
        // A mode switch ends any active layout session (NIC-142).
        endActiveLayoutSession()
        // Re-theme the dashboard by emitting the target mode's snapshot.
        let snapshot = composeState(activeModeID: input.modeId)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        await reapplyCollapseBucket(enteredModeID: input.modeId)
        return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "ok"))
    }

    // MARK: - Collapse / expand all (NIC-143)

    /// Toggles the collapse-all state of a mode: on collapse, captures the currently
    /// visible applications and hides them into the mode's session-only bucket; on
    /// expand, un-hides exactly that bucket and clears it. Uses the same permission-free
    /// app-level hide/unhide as "Windows Stored by Mode" (owner decision: hide, not
    /// Dock-minimize) and never re-confirms — it is a benign local view change. Collapsing
    /// an empty desktop is a no-op (nothing to hide, so the mode stays expanded). Emits
    /// `mode.windowcollapse.changed` so the bottom-bar icon reflects the new state.
    private func toggleModeCollapse(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ToggleModeCollapseInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "toggleModeCollapse requires a modeId.")
        }
        // Without the app-level window capability (pre-Mac, tests) we cannot hide or
        // return windows, so the collapse state cannot change — report it honestly.
        guard let windows = workspaceWindows else {
            return ok(request, payload: ToggleModeCollapseResult(
                collapsed: collapseStore.isCollapsed(modeID: input.modeId)
            ))
        }

        let collapsed: Bool
        if collapseStore.isCollapsed(modeID: input.modeId) {
            // Expand: un-hide only the apps this mode collapsed (windows opened since
            // are left as-is), then clear the bucket.
            let bucket = collapseStore.expand(modeID: input.modeId)
            if !bucket.isEmpty {
                _ = try? await windows.unhideApplications(bundleIDs: bucket)
            }
            collapsed = false
        } else {
            // Collapse: capture the currently visible apps (the capability already
            // excludes the host app) and hide them. Nothing visible ⇒ no-op.
            let visible = (try? await windows.visibleApplicationBundleIDs()) ?? []
            guard !visible.isEmpty else {
                return ok(request, payload: ToggleModeCollapseResult(collapsed: false))
            }
            _ = try? await windows.hideApplications(bundleIDs: visible)
            collapseStore.collapse(modeID: input.modeId, bundleIDs: visible)
            collapsed = true
        }
        emit(BridgeEventFactory.windowCollapseChangedEvent(
            modeId: input.modeId, collapsed: collapsed,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ToggleModeCollapseResult(collapsed: collapsed))
    }

    /// Close all windows across every mode (NIC-143): quits every open regular
    /// application (except CerebralHelm). Routes through the command bus like any
    /// destructive tool — `apps.quitall` is `destructive`, so the policy engine gates
    /// it on a confirmation. This mirrors `submitCommand`: register the awaiting
    /// confirmation (pushing the disclosure) and return an accepting receipt; the quit
    /// happens only after the user approves through the normal confirmation flow.
    private func closeAllWindows(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let outcome = await runtime.submit("quit-all", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        return ok(request, payload: receipt(for: outcome))
    }

    // MARK: - Window navigator (NIC-143)

    /// The window-navigator inventory: every open window grouped by application. A
    /// direct-capability read, no confirmation. Degrades to an honest empty list when
    /// the capability is absent (pre-Mac / before the live AX adapter lands).
    private func listWindows(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let groups = (try? await appWindows?.listWindows()) ?? []
        let apps = groups.map { group in
            WindowGroupDTO(
                bundleId: group.bundleID,
                appName: group.appName,
                appIconPng: group.appIconPNGBase64,
                windows: group.windows.map { WindowDTO(id: $0.id, title: $0.title, minimized: $0.minimized) }
            )
        }
        return ok(request, payload: WindowInventory(apps: apps))
    }

    /// Shared body for the minimize/surface/close window actions (NIC-143): resolve the
    /// window id and run the action, reporting whether it took effect. A benign local
    /// view change (surface/minimize) or the equivalent of the window's own close button
    /// — direct-capability, no per-press confirmation. No-op `ok: false` when the
    /// capability is absent or the id is unknown.
    private func windowAction(
        _ request: CerebralHelmBridgeOperationRequest,
        _ act: @escaping (any AppWindowsCapability, String) async throws -> Bool
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: WindowRefInput = decodePayload(request), !input.windowId.isEmpty else {
            return invalidInput(request, "a window action requires a windowId.")
        }
        guard let capability = appWindows else {
            return ok(request, payload: WindowActionResult(ok: false))
        }
        let affected = (try? await act(capability, input.windowId)) ?? false
        return ok(request, payload: WindowActionResult(ok: affected))
    }

    /// After a mode switch, re-apply the entered mode's collapse bucket (NIC-143):
    /// "Windows Stored by Mode" restore-on-enter may have un-hidden apps the user had
    /// collapsed, so re-hide anything still in that mode's bucket — the collapse bucket
    /// is authoritative for its mode (owner: "a window state by mode, like open/closed").
    /// Always (re)announces the entered mode's collapse state so the bottom-bar icon is
    /// correct for the mode now shown, even when nothing needed re-hiding.
    private func reapplyCollapseBucket(enteredModeID: String) async {
        let collapsed = collapseStore.isCollapsed(modeID: enteredModeID)
        if collapsed,
           let bucket = collapseStore.bucket(modeID: enteredModeID), !bucket.isEmpty,
           let windows = workspaceWindows {
            _ = try? await windows.hideApplications(bundleIDs: bucket)
        }
        emit(BridgeEventFactory.windowCollapseChangedEvent(
            modeId: enteredModeID, collapsed: collapsed,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    // MARK: - Layout session (NIC-142)

    /// Enters layout mode for a mode: starts the bottom-bar layout session from the
    /// mode's authored layout (emitting `layout.session.changed`) and opens its
    /// windows by running the synthesized `open-<mode>-layout` workflow through the
    /// command bus — a normal, aggregate-confirmed sequence of narrow tool steps.
    ///
    /// The session is populated from the *authored config*, not the workflow result:
    /// the workflow is confirmation-gated (`local_write`), so it may still be
    /// awaiting the user's approval when this returns. The bar reflects the layout's
    /// intent immediately; the windows open once approved.
    private func openLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: OpenLayoutInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "openLayout requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: OpenLayoutResult(accepted: false, modeId: input.modeId))
        }
        guard let layout = resolveLayout(modeID: input.modeId) else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "no_layout",
                message: "Mode \"\(input.modeId)\" has no authored layout."
            )
        }

        let session = buildLayoutSession(modeID: input.modeId, layout: layout)
        setActiveLayoutSession(session)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: session.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))

        // Force the correct setup on open (NIC-142, owner direction 2026-07-15): open and
        // arrange EVERY static window + hotswap target from the authored (override-merged)
        // layout so nothing cold-starts on toggle, then hide the inactive hotswaps.
        // Direct capability calls (authorized once at open; the same executor bypass as
        // toggle/close). This supersedes the synthesized-workflow open, which read the
        // SHIPPED layout and so fought the override-merged session's frames.
        await openAndArrangeLayout(layout: layout, session: session)

        return ok(request, payload: OpenLayoutResult(accepted: true, modeId: input.modeId))
    }

    /// Opens + arranges an entire layout on entry (NIC-142): every static window and
    /// EVERY hotswap target is opened and arranged into its frame from the resolved
    /// (override-merged) layout, then the inactive hotswap apps are hidden so only the
    /// active one shows. Opening all hotswaps up front means toggling never cold-starts
    /// a window (owner direction). URL windows are opened but not arranged (a URL is not
    /// an app; browser placement is a later increment). App-level hide, so two hotswaps
    /// sharing a bundle (e.g. two Chrome profiles) are never hidden out from under the
    /// active one.
    private func openAndArrangeLayout(layout: Layout, session: LayoutSession) async {
        // ref → bundle id for app windows, from the already-resolved session.
        var appBundleByRef: [String: String] = [:]
        for window in session.windows where window.bundleID != nil {
            appBundleByRef[window.ref] = window.bundleID
        }
        for target in session.quickToggle?.targets ?? [] where target.bundleID != nil {
            appBundleByRef[target.ref] = target.bundleID
        }
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )

        // The window to arrange for a ref: the app bundle for an app, or the browser
        // bundle for a URL (Chrome for a profiled URL, else the default browser) — a
        // URL "window" is its browser (NIC-142).
        func arrangeBundle(_ ref: String, kind: Kind) -> String? {
            switch kind {
            case .app:
                return appBundleByRef[ref]
            case .url:
                guard let entry = references?.urls[ref] else { return nil }
                return entry.profile != nil ? UserChromeProfileReferences.chromeBundleID : defaultBrowserBundleID?()
            }
        }
        func arrange(_ ref: String, kind: Kind, _ frameRaw: String) async {
            guard let bundle = arrangeBundle(ref, kind: kind), let frame = WindowFrame(rawValue: frameRaw) else {
                return
            }
            _ = try? await window?.arrange(bundleID: bundle, frame: frame, display: .primary)
        }
        func surface(_ ref: String, kind: Kind) async {
            switch kind {
            case .app: _ = try? await app?.open(appID: ref)
            case .url: _ = try? await url?.open(urlID: ref)
            }
        }

        // Static windows: open + arrange (apps and URLs).
        for staticWindow in layout.windows {
            await surface(staticWindow.ref, kind: staticWindow.kind)
            await arrange(staticWindow.ref, kind: staticWindow.kind, staticWindow.frame.rawValue)
        }

        // Hotswap targets: open + arrange ALL, then hide every inactive app (URL targets
        // share the browser window, so they are surfaced by tab rather than hidden).
        guard let toggle = layout.quickToggle else { return }
        let frameRaw = toggle.frame.rawValue
        let activeRef = session.quickToggle?.activeRef ?? toggle.targets.first?.ref
        for target in toggle.targets {
            await surface(target.ref, kind: target.kind)
            await arrange(target.ref, kind: target.kind, frameRaw)
        }
        let activeBundle = activeRef.flatMap { appBundleByRef[$0] }
        let inactiveBundles = Set(toggle.targets.compactMap { target -> String? in
            guard target.kind == .app, let bundle = appBundleByRef[target.ref], bundle != activeBundle else {
                return nil
            }
            return bundle
        })
        if !inactiveBundles.isEmpty {
            _ = try? await workspaceWindows?.hideApplications(bundleIDs: Array(inactiveBundles))
        }
        // Bring the active hotswap forward and re-arrange it last so it shows in place.
        if let activeRef, let active = toggle.targets.first(where: { $0.ref == activeRef }) {
            await surface(active.ref, kind: active.kind)
            await arrange(active.ref, kind: active.kind, frameRaw)
        }
    }

    /// The browser bundle id to arrange for a layout URL window (NIC-142): Chrome for a
    /// profiled URL, else the default browser. nil when the ref is unknown or no default
    /// browser resolver is wired.
    private func urlBrowserBundleID(forURLRef ref: String) -> String? {
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        guard let entry = references?.urls[ref] else { return nil }
        return entry.profile != nil ? UserChromeProfileReferences.chromeBundleID : defaultBrowserBundleID?()
    }

    /// Exits layout mode: hides the session's app windows (permission-free, like
    /// "Windows Stored by Mode") and clears the session, emitting a null
    /// `layout.session.changed`. URL windows have no bundle id and are left open.
    private func closeLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let session = takeActiveLayoutSession() else {
            return ok(request, payload: CloseLayoutResult(closed: false))
        }
        let bundleIDs = session.appBundleIDs
        if let windows = workspaceWindows, !bundleIDs.isEmpty {
            _ = try? await windows.hideApplications(bundleIDs: bundleIDs)
        }
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: CloseLayoutResult(closed: true))
    }

    /// Swaps the dynamic quick-toggle slot to a target (NIC-142): hides the
    /// previously-shown target's app window and surfaces the pressed one — an app is
    /// re-opened/activated, a URL surfaces its tab through the runtime's shared
    /// tab-surfacing registry. No confirmation: the session was authorized when the
    /// layout opened (owner decision). A URL target that was previously shown cannot
    /// be hidden (its window is the shared browser), so the new target surfaces over it.
    private func toggleLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ToggleLayoutInput = decodePayload(request), !input.ref.isEmpty else {
            return invalidInput(request, "toggleLayout requires a ref.")
        }
        guard
            let session = peekActiveLayoutSession(),
            let toggle = session.quickToggle,
            let target = toggle.targets.first(where: { $0.ref == input.ref })
        else {
            // No active layout, no quick-toggle slot, or an unknown target.
            return ok(request, payload: ToggleLayoutResult(accepted: false))
        }
        if toggle.activeRef == input.ref {
            return ok(request, payload: ToggleLayoutResult(accepted: true))  // already shown
        }

        // Hide the previously-shown app target (permission-free); a URL prior can't
        // be hidden — the pressed target simply surfaces over the shared browser.
        if let previous = toggle.targets.first(where: { $0.ref == toggle.activeRef }),
           previous.kind == "app", let bundleID = previous.bundleID, let windows = workspaceWindows {
            _ = try? await windows.hideApplications(bundleIDs: [bundleID])
        }

        // Surface the pressed target directly (authorized once at open; no re-prompt),
        // then re-arrange it into the hotswap frame — the user may have moved it, and a
        // freshly surfaced window lands wherever the app put it, so force it back to the
        // slot on every swap (NIC-142).
        let frame = toggle.frame.flatMap(WindowFrame.init(rawValue:))
        switch target.kind {
        case "url":
            _ = try? await url?.open(urlID: target.ref)
            // A URL "window" is its browser: Chrome for a profiled URL, else the default.
            if let frame, let bundleID = urlBrowserBundleID(forURLRef: target.ref) {
                _ = try? await window?.arrange(bundleID: bundleID, frame: frame, display: .primary)
            }
        default:
            _ = try? await app?.open(appID: target.ref)
            if let frame, let bundleID = target.bundleID {
                _ = try? await window?.arrange(bundleID: bundleID, frame: frame, display: .primary)
            }
        }

        let updated = session.withActiveToggle(input.ref)
        setActiveLayoutSession(updated)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: updated.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ToggleLayoutResult(accepted: true))
    }

    /// Pins an app/URL reference as a quick-toggle target on a mode's layout
    /// (NIC-142) and persists it through the validated config-override path, so the
    /// pin survives restarts and drives the next open. When a session for that mode
    /// is active, the new target appears in the bar immediately. Requires the layout
    /// to already have a dynamic slot (the frame the pinned window would occupy).
    private func pinLayoutWindow(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: PinLayoutWindowInput = decodePayload(request),
              !input.modeId.isEmpty, !input.ref.isEmpty else {
            return invalidInput(request, "pinLayoutWindow requires a modeId and ref.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Pinning requires a durable workspace."
            )
        }
        guard let layout = resolveLayout(modeID: input.modeId) else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "no_layout",
                message: "Mode \"\(input.modeId)\" has no authored layout."
            )
        }
        guard let toggle = layout.quickToggle else {
            return ok(request, payload: PinLayoutWindowResult(
                accepted: false, errors: ["This layout has no dynamic slot to pin a window to."]
            ))
        }

        // Resolve the ref's kind from the reference catalog — this is also the
        // existence check (an id in neither catalog cannot be pinned).
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace.stateRoot
        )
        let kind: Kind
        if references?.apps[input.ref] != nil {
            kind = .app
        } else if references?.urls[input.ref] != nil {
            kind = .url
        } else {
            return ok(request, payload: PinLayoutWindowResult(
                accepted: false, errors: ["\"\(input.ref)\" is not a configured app or URL reference."]
            ))
        }

        // Already a target → accepted no-op (idempotent pin).
        if toggle.targets.contains(where: { $0.ref == input.ref }) {
            return ok(request, payload: PinLayoutWindowResult(accepted: true, errors: []))
        }

        let newLayout = Layout(
            display: layout.display,
            quickToggle: QuickToggle(frame: toggle.frame, targets: toggle.targets + [Target(kind: kind, ref: input.ref)]),
            windows: layout.windows
        )
        // Preserve any existing override fields (e.g. pinned quick apps) — the
        // override file replaces wholesale, so a layout-only write must not drop them.
        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions,
            id: input.modeId,
            layout: encodePayload(newLayout),
            quickApps: existing?.quickApps,
            schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            refreshActiveLayoutSession(modeID: input.modeId, layout: newLayout)
            return ok(request, payload: PinLayoutWindowResult(accepted: true, errors: []))
        case let .rejected(errors):
            return ok(request, payload: PinLayoutWindowResult(accepted: false, errors: errors.map(\.message)))
        }
    }

    /// Adds a quick-toggle target to the ACTIVE layout session for this session only
    /// (NIC-142) — the bottom-bar "+" live add. Unlike `pinLayoutWindow` it does NOT
    /// persist to the override: the target lives in the in-memory session and is gone
    /// when the layout closes or the mode switches. Requires an active session with a
    /// dynamic slot; idempotent for a ref already present. No confirmation — the
    /// session was authorized when the layout opened.
    private func addLayoutTarget(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: AddLayoutTargetInput = decodePayload(request), !input.ref.isEmpty else {
            return invalidInput(request, "addLayoutTarget requires a ref.")
        }
        guard let session = peekActiveLayoutSession(), let toggle = session.quickToggle else {
            // No active layout or no dynamic slot to add into (a session-only add
            // cannot mint a slot).
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        // Already a target → accepted no-op, no re-emit (idempotent).
        if toggle.targets.contains(where: { $0.ref == input.ref }) {
            return ok(request, payload: AddLayoutTargetResult(accepted: true))
        }
        // Resolve the ref against the reference catalog — the existence check plus the
        // kind/label/bundle id the session window needs.
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        let window: LayoutSessionWindow
        if let entry = references?.apps[input.ref] {
            window = LayoutSessionWindow(ref: input.ref, kind: "app", label: entry.label, bundleID: entry.target)
        } else if let entry = references?.urls[input.ref] {
            window = LayoutSessionWindow(ref: input.ref, kind: "url", label: entry.label, bundleID: nil)
        } else {
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        guard let updated = session.withAddedToggleTarget(window) else {
            return ok(request, payload: AddLayoutTargetResult(accepted: false))
        }
        setActiveLayoutSession(updated)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: updated.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: AddLayoutTargetResult(accepted: true))
    }

    /// Writes a full authored layout to a mode's override (NIC-142 authoring) — the
    /// Save side of the Settings layout editor. Validates every reference against the
    /// catalog and the structure through the same override write path; preserves any
    /// existing override fields (e.g. pinned quick apps).
    private func updateLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: UpdateLayoutInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "updateLayout requires a modeId and layout.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Authoring a layout requires a durable workspace."
            )
        }
        guard let layout = Layout.from(raw: input.layout) else {
            return ok(request, payload: UpdateLayoutResult(accepted: false, errors: ["The layout is malformed."]))
        }
        // Reference-existence: every window and toggle target must name a configured
        // app or URL reference (the same gate quick-app pinning uses).
        let known = configuredReferenceIDs()
        var unknown: Set<String> = []
        for window in layout.windows where !known.contains(window.ref) { unknown.insert(window.ref) }
        for target in layout.quickToggle?.targets ?? [] where !known.contains(target.ref) { unknown.insert(target.ref) }
        guard unknown.isEmpty else {
            return ok(request, payload: UpdateLayoutResult(
                accepted: false,
                errors: unknown.sorted().map { "\"\($0)\" is not a configured app or URL reference." }
            ))
        }

        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions, id: input.modeId, layout: input.layout,
            quickApps: existing?.quickApps, schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            refreshActiveLayoutSession(modeID: input.modeId, layout: layout)
            return ok(request, payload: UpdateLayoutResult(accepted: true, errors: []))
        case let .rejected(errors):
            return ok(request, payload: UpdateLayoutResult(accepted: false, errors: errors.map(\.message)))
        }
    }

    /// Proposes a layout from the currently-arranged windows (NIC-142 live capture):
    /// each visible app that resolves to a configured reference, snapped to the named
    /// frame it most occupies. The editor lets the user refine and Save (updateLayout).
    /// macOS-only — degrades honestly without the AX window capability.
    private func captureLayout(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let window, let workspaceWindows else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "capture_unavailable",
                message: "Layout capture is available on the macOS host."
            )
        }
        let visible: WindowRect
        do {
            guard let frame = try await window.visibleFrame() else {
                return errorResponse(
                    request, category: .unavailableCapability,
                    code: "no_display", message: "No display is available to capture."
                )
            }
            visible = frame
        } catch {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "capture_denied",
                message: "Layout capture needs the Accessibility permission."
            )
        }

        let refByBundle = appReferencesByTarget()
        let visibleApps = (try? await workspaceWindows.visibleApplicationBundleIDs()) ?? []
        var windows: [CaptureWindow] = []
        for bundleID in visibleApps {
            guard let ref = refByBundle[bundleID] else { continue }  // configured references only
            guard let rect = try? await window.captureFrame(bundleID: bundleID) else { continue }
            let frame = WindowFrameGeometry.snap(rect, in: visible)
            windows.append(CaptureWindow(ref: ref, kind: "app", frame: frame.rawValue))
        }
        return ok(request, payload: CaptureLayoutResult(windows: windows))
    }

    /// The mode's effective layout (NIC-142): the override-merged layout when a
    /// workspace is bound (so a user's pins drive open), else the shipped layout.
    private func resolveLayout(modeID: String) -> Layout? {
        if let workspace, case let .activated(config) = ConfigLoader(workspace: workspace).load() {
            return config.mode(id: modeID)?.layout
        }
        return ModeLayoutCatalog.load(configDirectory: configDirectory)[modeID]
    }

    private func readOverride(modeID: String, workspace: WorkspacePaths) -> CerebralHelmModeOverride? {
        let url = workspace.overridesDirectory.appendingPathComponent("\(modeID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CerebralHelmModeOverride(data: data)
    }

    /// Rebuilds the active session for `modeID` from a changed layout, keeping the
    /// currently-shown quick-toggle target, and re-emits it.
    private func refreshActiveLayoutSession(modeID: String, layout: Layout) {
        guard let current = peekActiveLayoutSession(), current.modeID == modeID else { return }
        var refreshed = buildLayoutSession(modeID: modeID, layout: layout)
        if let active = current.quickToggle?.activeRef {
            refreshed = refreshed.withActiveToggle(active)
        }
        setActiveLayoutSession(refreshed)
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: refreshed.snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// Ends an active layout session without hiding windows (a mode switch already
    /// owns the outgoing mode's window behavior). No-op when none is active.
    private func endActiveLayoutSession() {
        guard takeActiveLayoutSession() != nil else { return }
        emit(BridgeEventFactory.layoutSessionChangedEvent(
            session: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// Resolves an authored layout into a session: each window/toggle target's
    /// human label and (for apps) bundle id, looked up in the reference catalog.
    private func buildLayoutSession(modeID: String, layout: Layout) -> LayoutSession {
        let references = try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )
        func resolve(ref: String, kind: Kind) -> LayoutSessionWindow {
            switch kind {
            case .app:
                let entry = references?.apps[ref]
                return LayoutSessionWindow(ref: ref, kind: "app", label: entry?.label ?? ref, bundleID: entry?.target)
            case .url:
                let entry = references?.urls[ref]
                return LayoutSessionWindow(ref: ref, kind: "url", label: entry?.label ?? ref, bundleID: nil)
            }
        }
        let windows = layout.windows.map { resolve(ref: $0.ref, kind: $0.kind) }
        let toggle = layout.quickToggle.flatMap { qt -> LayoutSessionToggle? in
            guard let first = qt.targets.first else { return nil }
            return LayoutSessionToggle(
                activeRef: first.ref,
                targets: qt.targets.map { resolve(ref: $0.ref, kind: $0.kind) },
                frame: qt.frame.rawValue
            )
        }
        return LayoutSession(modeID: modeID, windows: windows, quickToggle: toggle)
    }

    private func setActiveLayoutSession(_ session: LayoutSession?) {
        layoutLock.lock(); defer { layoutLock.unlock() }
        activeLayoutSession = session
    }

    private func takeActiveLayoutSession() -> LayoutSession? {
        layoutLock.lock(); defer { layoutLock.unlock() }
        let session = activeLayoutSession
        activeLayoutSession = nil
        return session
    }

    private func peekActiveLayoutSession() -> LayoutSession? {
        layoutLock.lock(); defer { layoutLock.unlock() }
        return activeLayoutSession
    }

    private func captureNote(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CaptureNoteInput = decodePayload(request), !input.title.isEmpty else {
            return invalidInput(request, "captureNote requires a title.")
        }
        // note.capture is a confirmation-gated local_write, so this enters the bus and
        // the disclosure is pushed to the UI. The note is written after the user
        // approves; the returned id is the command handle (see the captureNote contract
        // note — a synchronous noteId is not possible for a gated capture).
        let text = input.body.isEmpty ? input.title : "\(input.title)\n\(input.body)"
        let outcome = await runtime.submit("note \(text)", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        switch outcome {
        case let .completed(commandID, _, result):
            if let data = result?.output, let output = try? CerebralHelmNoteCaptureOutput(data: data) {
                return ok(request, payload: CaptureNoteResult(noteId: output.noteID))
            }
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case .rejected:
            return errorResponse(
                request, category: .invalidInput,
                code: "note_rejected", message: "The note could not be parsed."
            )
        }
    }

    private func runSpeedTest(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        // network.speed.test is a read_only tool — it never gates on confirmation,
        // so this resolves synchronously with the measurement (NIC-135). The bounded
        // ~30s networkQuality run happens inside runtime.submit; the caller awaits it
        // while the widget animates its ring.
        let outcome = await runtime.submit("speedtest", source: .dashboard)
        guard case let .completed(_, _, result) = outcome,
              let data = result?.output,
              let output = try? CerebralHelmNetworkSpeedTestOutput(data: data)
        else {
            // The tool could not run, or produced no parseable output: an honest
            // unavailable, never a fabricated figure.
            return ok(request, payload: SpeedTestResult(
                status: "unavailable", downloadMbps: nil, uploadMbps: nil, testedAt: nil
            ))
        }
        return ok(request, payload: SpeedTestResult(
            status: output.status.rawValue,
            downloadMbps: output.downloadMbps,
            uploadMbps: output.uploadMbps,
            testedAt: output.testedAt
        ))
    }

    /// Stores an API credential in the Keychain behind a logical reference (NIC-134). The value
    /// is trimmed of surrounding whitespace (a pasted key often carries a trailing newline) and
    /// written through ``SecretManaging/store(reference:value:)``; the response reports presence
    /// only — it never echoes the value, and the value never touches config or a log (FR-CFG-03,
    /// FR-OBS-03). A store overwrites in place, so re-entering a key corrects a wrong one.
    private func storeSecret(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: StoreSecretInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "storeSecret requires a reference.")
        }
        let value = input.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return invalidInput(request, "Enter a value to store.")
        }
        guard let secretStore else {
            return errorResponse(
                request, category: .unavailableCapability, code: "secret_store_unavailable",
                message: "Storing a secret requires the macOS host."
            )
        }
        do {
            try await secretStore.store(reference: input.reference, value: value)
            // Nudge any live consumer keyed on this secret (e.g. the releases producer) so the
            // widget reflects a just-entered key at once, not on its next slow tick (NIC-134).
            onSecretStored?(input.reference)
            return ok(request, payload: StoreSecretResult(reference: input.reference, stored: true))
        } catch {
            // Deliberately generic: never surface the value or a raw keychain diagnostic.
            return errorResponse(
                request, category: .unavailableCapability, code: "secret_store_failed",
                message: "That secret couldn't be stored. Check the reference name and try again."
            )
        }
    }

    /// Reports whether a logical secret reference is bound, without exposing the value (NIC-134) —
    /// so the settings field can honestly show "Set" vs "Not set" on load. A host without a secret
    /// store, or a resolve failure, reports `bound: false` (an honest "not set") rather than an
    /// error, so the field still renders.
    private func getSecretStatus(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SecretStatusInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "getSecretStatus requires a reference.")
        }
        guard let secretStore else {
            return ok(request, payload: SecretStatusResult(reference: input.reference, bound: false))
        }
        let resolution = try? await secretStore.resolve(reference: input.reference)
        return ok(request, payload: SecretStatusResult(
            reference: input.reference, bound: resolution?.isResolved ?? false
        ))
    }

    /// Removes a stored secret (NIC-133) — the "disconnect" path (e.g. Spotify's `spotify_oauth`
    /// blob, or clearing a provider key). Idempotent: deleting an absent reference reports
    /// `deleted: false` without erroring, so a disconnect on an already-disconnected account is a
    /// clean no-op. The value is never read or echoed.
    private func deleteSecret(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SecretStatusInput = decodePayload(request), !input.reference.isEmpty else {
            return invalidInput(request, "deleteSecret requires a reference.")
        }
        guard let secretStore else {
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: false))
        }
        do {
            try await secretStore.delete(reference: input.reference)
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: true))
        } catch {
            // Absent (or an unreadable store) — nothing to remove, an honest idempotent no-op.
            return ok(request, payload: DeleteSecretResult(reference: input.reference, deleted: false))
        }
    }

    /// Runs the Spotify OAuth connect flow (NIC-133): opens the browser to Spotify's consent page,
    /// captures the redirect, exchanges the code, and persists the tokens to the Keychain — all
    /// inside the injected `spotifyConnect` closure (the Mac coordinator). The response reports only
    /// `connected` and the granted `scope`; the tokens never cross back. Failures degrade to an
    /// honest message and never leak a diagnostic: no Client ID / user declined → guidance; a
    /// Spotify rejection or timeout → a generic retry message.
    private func connectSpotify(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let spotifyConnect else {
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_unavailable",
                message: "Connecting Spotify requires the macOS host."
            )
        }
        do {
            let connection = try await spotifyConnect()
            return ok(request, payload: ConnectSpotifyResult(connected: true, scope: connection.scope))
        } catch let error as SpotifyPlaybackError {
            let message: String
            switch error {
            case .credentialsMissing:
                message = "Add your Spotify Client ID in Settings → Setup, then connect."
            case .notConnected:
                message = "Spotify didn't accept the connection. Please try connecting again."
            case .providerFailed:
                message = "Couldn't connect to Spotify. Please try again."
            }
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_failed", message: message
            )
        } catch {
            return errorResponse(
                request, category: .unavailableCapability, code: "spotify_connect_failed",
                message: "Couldn't connect to Spotify. Please try again."
            )
        }
    }

    private func searchNotes(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SearchNotesInput = decodePayload(request), !input.text.isEmpty else {
            // An empty query yields no results rather than an error (empty search box).
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let outcome = await runtime.submit("search \(input.text)", source: .dashboard)
        guard
            case let .completed(_, _, result) = outcome,
            let data = result?.output,
            let output = try? CerebralHelmNoteSearchOutput(data: data)
        else {
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let hits = output.results.map {
            NoteHit(noteId: $0.noteID, title: $0.title, excerpt: $0.excerpt)
        }
        return ok(request, payload: SearchNotesResult(results: hits))
    }

    /// Read-only application discovery (NIC-119): wraps the `apps` command so the
    /// More Apps picker rides the same command bus as every other input source,
    /// and unwraps the tool output for the dashboard. Pre-Mac (or on any tool
    /// failure) this is a structured unavailable — the picker renders honestly.
    private func listApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let outcome = await runtime.submit("apps", source: .dashboard)
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let data = result?.output,
            let output = try? CerebralHelmAppsListOutput(data: data)
        else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "apps_list_unavailable",
                message: "Application discovery is unavailable."
            )
        }
        // Auto-mint (owner decision, 2026-07-06): any discovered app that no
        // reference targets gets one minted now, so a mid-session install is
        // pinnable immediately. Then live-reload the shared reference catalog so
        // `open <minted-id>` resolves this session too (NIC-150): the parser and —
        // on the macOS shell — the app.open target map both read the runtime's
        // reference store, exactly as `addUrlReference` reloads after minting a
        // URL. Without the reload a freshly installed app opened only after a
        // relaunch (the store composes once at startup).
        if let workspace {
            let shipped = (try? ReferenceCatalogLoader.load(configDirectory: configDirectory))
                .map { Array($0.apps.values) } ?? []
            UserAppReferences.mint(
                discovered: output.apps.map {
                    UserAppReferences.DiscoveredApp(bundleID: $0.bundleID, name: $0.name)
                },
                shipped: shipped,
                stateRoot: workspace.stateRoot
            )
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
        }
        // Join discovered apps onto the configured app references by bundle id
        // (the reference `target`). `referenceId` is the pinnable key: only a
        // discovered app backed by a configured reference may enter a mode's
        // quick-app slots (NIC-119 — no arbitrary paths, ever).
        let referencesByTarget = appReferencesByTarget()
        let apps = output.apps.map {
            DiscoveredApp(
                bundleId: $0.bundleID,
                name: $0.name,
                iconPng: $0.iconPNG,
                referenceId: referencesByTarget[$0.bundleID]
            )
        }
        return ok(request, payload: ListAppsResult(apps: apps, truncated: output.truncated))
    }

    /// Sets a mode's quick-app slots through the validated config-write path
    /// (NIC-119c): every id must name a configured app reference (existence
    /// check), then `ConfigOverrideWriter` writes the per-mode override and
    /// re-activates the layered config — a rejected candidate is rolled back on
    /// disk and reported, never half-applied. An applied write emits
    /// `mode.quickapps.changed` so every surface's tiles refresh immediately.
    private func updateQuickApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: UpdateQuickAppsInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "updateQuickApps requires a modeId and quickApps array.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Pinning requires a durable workspace."
            )
        }
        // A quick-app slot may hold any configured app or URL reference id (NIC-146):
        // a pinned URL is just another quick-app tile, so both catalogs are valid
        // pin targets. Arbitrary paths/URLs still can't enter — only ids that name a
        // reference the catalog already resolves.
        let known = configuredReferenceIDs()
        let unknown = input.quickApps.filter { !known.contains($0) }
        guard unknown.isEmpty else {
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: unknown.map { "\"\($0)\" is not a configured app or URL reference." }
            ))
        }

        // Preserve any existing override fields (e.g. an authored layout, NIC-142) —
        // the override file replaces wholesale, so a quick-apps write must not drop them.
        let existing = readOverride(modeID: input.modeId, workspace: workspace)
        let override = CerebralHelmModeOverride(
            extensions: existing?.extensions, id: input.modeId, layout: existing?.layout,
            quickApps: input.quickApps, schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            // Refresh every surface: a dedicated per-widget event carries the new
            // slots (NIC-149). `config.changed` cannot — its snapshot omits `modes`
            // and the dashboard ignores it when the active mode is unchanged.
            emit(BridgeEventFactory.quickAppsChangedEvent(
                modeId: input.modeId, quickApps: input.quickApps,
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: true, quickApps: input.quickApps, errors: []
            ))
        case let .rejected(errors):
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: errors.map(\.message)
            ))
        }
    }

    /// Configured app references keyed by their bundle-id target.
    private func appReferencesByTarget() -> [String: String] {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return [:]
        }
        return Dictionary(
            references.apps.values.map { ($0.target, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every configured reference id the parser resolves — app and URL, shipped and
    /// user-minted. This is the pinnable-id set (`updateQuickApps`, NIC-146) and the
    /// uniqueness domain a newly minted URL id must avoid, so a pinned URL's
    /// `open <id>` can never resolve ambiguously against an app of the same id.
    private func configuredReferenceIDs() -> Set<String> {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return []
        }
        return Set(references.apps.keys).union(references.urls.keys)
    }

    /// Mints a user URL reference through the same auto-minting mechanism as user
    /// app references (NIC-146): a user-entered URL becomes a configured reference,
    /// so it can then be pinned as a quick app through the validated write path. Only
    /// `http`/`https` URLs mint — never an arbitrary scheme. Requires a durable
    /// workspace (the state root the user catalog lives under).
    private func addUrlReference(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: AddUrlReferenceInput = decodePayload(request) else {
            return invalidInput(request, "addUrlReference requires a url.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "url_references_unavailable",
                message: "Adding a URL requires a durable workspace."
            )
        }
        switch UserURLReferences.add(
            url: input.url, label: input.label, profile: input.profile,
            existingIDs: configuredReferenceIDs(), stateRoot: workspace.stateRoot
        ) {
        case let .success(entry):
            // Live-reload the shared catalog so the minted id resolves this session:
            // the runtime's parser (`open <id>`) and — on the macOS shell — the
            // url.open capability map both read the same store (NIC-146). Without this
            // the URL would open only after a relaunch.
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
            // Kick off the favicon fetch now so the icon is ready by the time the
            // dashboard re-reads `listUrls` after pinning (NIC-147). The minted DTO
            // carries no icon yet — the tile shows its placeholder until it lands.
            warmFavicons([entry])
            return ok(request, payload: AddUrlReferenceResult(
                accepted: true,
                reference: urlReferenceDTO(entry, cache: faviconCache()),
                errors: []
            ))
        case let .failure(error):
            return ok(request, payload: AddUrlReferenceResult(
                accepted: false, reference: nil, errors: [Self.message(for: error)]
            ))
        }
    }

    private static func message(for error: UserURLReferences.AddError) -> String {
        switch error {
        case .emptyURL: return "Enter a URL to add."
        case .invalidURL: return "That doesn't look like a valid web address."
        case .unsupportedScheme: return "Only http and https web addresses can be added."
        case .invalidProfile: return "The Chrome profile can only contain letters, numbers, spaces, dots, hyphens, and underscores."
        }
    }

    /// The configured URL references (shipped + user-minted), sorted by label — the
    /// dashboard's read feed for rendering pinned URL tiles with their real labels
    /// (NIC-146). Apps have `listApps` discovery for this; URLs have no discovery,
    /// so this is their equivalent. Workspace-less hosts still see the shipped set.
    private func listUrls(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        let urls = (try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )).map { Array($0.urls.values) } ?? []
        let cache = faviconCache()
        let sorted = urls
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map { urlReferenceDTO($0, cache: cache) }
        // Warm any cold favicons in the background; a landed icon upgrades its tile
        // live via `mode.quickapps.changed` (NIC-147). The read returns immediately.
        warmFavicons(urls)
        return ok(request, payload: ListUrlsResult(urls: sorted))
    }

    // MARK: - Chrome profiles (NIC-151)

    /// The user's Chrome profiles for the profile dropdown + avatar badges (NIC-151):
    /// directory name (the `--profile-directory` value a reference stores), display
    /// name, and an optional avatar PNG. An empty list on a host without the
    /// capability (non-Mac, tests) — the UI then offers no profile choices.
    private func listChromeProfiles(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let profiles = (try? await chromeProfiles?.listProfiles()) ?? []
        // The pinned Chrome-profile app references (NIC-151), so the dashboard can
        // render a pinned "Chrome — Work" tile with its label + avatar (by matching
        // the reference's profile directory back to a discovered profile).
        let references = (try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )).map { catalog in
            catalog.apps.values
                .filter { $0.target == UserChromeProfileReferences.chromeBundleID && $0.profile != nil }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
                .map { AppReferenceDTO(id: $0.id, label: $0.label, target: $0.target, profile: $0.profile) }
        } ?? []
        return ok(request, payload: ChromeProfilesResult(
            profiles: profiles.map {
                ChromeProfileDTO(directory: $0.directory, name: $0.name, iconPng: $0.iconPNGBase64)
            },
            references: references
        ))
    }

    /// Lists the user's calendars for the Settings calendar→mode mapping (NIC-126). Requests
    /// Calendar access at point of use; a denied grant (or any read failure, or no provider) is an
    /// honest `authorized: false` with an empty list, which the Settings UI turns into a "grant
    /// Calendar access" prompt rather than a fabricated set of calendars.
    private func listCalendars(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let calendarProvider else {
            return ok(request, payload: CalendarsResult(authorized: false, calendars: []))
        }
        do {
            let calendars = try await calendarProvider.calendars()
            return ok(request, payload: CalendarsResult(
                authorized: true,
                calendars: calendars.map { CalendarDTO(id: $0.id, title: $0.title, colorHex: $0.colorHex) }
            ))
        } catch {
            return ok(request, payload: CalendarsResult(authorized: false, calendars: []))
        }
    }

    /// Mints an app reference that opens Google Chrome in a specific profile (NIC-151),
    /// so a Chrome profile can be pinned as a quick app the same way any app is. The
    /// minted reference targets `com.google.Chrome` and carries the profile directory,
    /// so `app.open` launches it with `--profile-directory` (NIC-151 increment 3).
    private func addChromeProfileReference(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: AddChromeProfileInput = decodePayload(request) else {
            return invalidInput(request, "addChromeProfileReference requires a profile directory.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "chrome_profiles_unavailable",
                message: "Pinning a Chrome profile requires a durable workspace."
            )
        }
        switch UserChromeProfileReferences.add(
            directory: input.directory, name: input.name,
            existingIDs: configuredReferenceIDs(), stateRoot: workspace.stateRoot
        ) {
        case let .success(entry):
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
            return ok(request, payload: AddChromeProfileResult(
                accepted: true,
                reference: AppReferenceDTO(id: entry.id, label: entry.label, target: entry.target, profile: entry.profile),
                errors: []
            ))
        case let .failure(error):
            return ok(request, payload: AddChromeProfileResult(
                accepted: false, reference: nil, errors: [Self.message(for: error)]
            ))
        }
    }

    private static func message(for error: UserChromeProfileReferences.AddError) -> String {
        switch error {
        case .emptyDirectory: return "Choose a Chrome profile to pin."
        case .invalidProfile: return "That Chrome profile name isn't valid."
        }
    }

    // MARK: - Favicons (NIC-147)

    private func faviconCache() -> FaviconCache? {
        workspace.map { FaviconCache(directory: $0.faviconCacheDirectory) }
    }

    private func urlReferenceDTO(_ entry: ReferenceEntry, cache: FaviconCache?) -> UrlReferenceDTO {
        UrlReferenceDTO(
            id: entry.id, label: entry.label, target: entry.target,
            iconPng: cache?.icon(forTarget: entry.target)?.base64EncodedString(),
            profile: entry.profile
        )
    }

    /// Fetches, in the background, the favicon for every reference whose origin has
    /// no cached hit or fresh miss — skipping origins already in flight. On success
    /// the PNG is cached and a `mode.quickapps.changed` event nudges the tiles to
    /// re-read `listUrls` (NIC-147 owner decision: reuse the per-widget event, so a
    /// freshly pinned URL shows its placeholder at once and upgrades once fetched).
    /// No-op without a favicon capability or a durable workspace.
    private func warmFavicons(_ references: [ReferenceEntry]) {
        guard let capability = faviconCapability, let cache = faviconCache() else { return }
        // One representative target per cold origin (favicons are per-origin).
        var targetByOrigin: [String: String] = [:]
        for entry in references {
            guard
                let origin = FaviconCache.origin(forTarget: entry.target),
                cache.needsFetch(forTarget: entry.target),
                targetByOrigin[origin] == nil
            else { continue }
            targetByOrigin[origin] = entry.target
        }
        let work = claimFaviconOrigins(Set(targetByOrigin.keys))
            .compactMap { origin in targetByOrigin[origin].map { (origin, $0) } }
        guard !work.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            var anyStored = false
            for (origin, target) in work {
                defer { self.releaseFaviconOrigin(origin) }
                guard let url = URL(string: target) else { continue }
                if let png = await capability.fetchFavicon(for: url) {
                    if cache.store(png: png, forTarget: target) { anyStored = true }
                } else {
                    cache.recordMiss(forTarget: target)
                }
            }
            if anyStored { self.emitFaviconRefresh() }
        }
    }

    /// Marks the given origins in flight and returns those not already fetching.
    private func claimFaviconOrigins(_ origins: Set<String>) -> [String] {
        faviconLock.lock(); defer { faviconLock.unlock() }
        let fresh = origins.subtracting(faviconInFlightOrigins)
        faviconInFlightOrigins.formUnion(fresh)
        return Array(fresh)
    }

    private func releaseFaviconOrigin(_ origin: String) {
        faviconLock.lock(); defer { faviconLock.unlock() }
        faviconInFlightOrigins.remove(origin)
    }

    /// Re-emits the active mode's `mode.quickapps.changed` (unchanged pins) so its
    /// tiles re-read `listUrls` and pick up newly cached favicons. Other modes pick
    /// theirs up on next view — `listUrls` reads the now-warm cache.
    private func emitFaviconRefresh() {
        let state = composeBootstrapState()
        let activeID = bootstrapModeID()
        guard let mode = state.modes.first(where: { $0.id == activeID }) ?? state.modes.first else { return }
        emit(BridgeEventFactory.quickAppsChangedEvent(
            modeId: mode.id, quickApps: mode.quickApps,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// The recent-activity read surface. A fresh session has no activity; the durable
    /// DB-backed history read is a follow-on increment, so this returns the honest
    /// empty envelope (the dashboard renders an empty feed rather than fabricated rows).
    private func getRecentActivity(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: RecentActivityEnvelope())
    }

    private func decideConfirmation(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: DecideConfirmationInput = decodePayload(request), !input.id.isEmpty else {
            return invalidInput(request, "decideConfirmation requires an id and decision.")
        }
        guard let token = takeToken(id: input.id) else {
            return errorResponse(
                request, category: .invalidInput,
                code: "unknown_confirmation", message: "No pending confirmation for \(input.id)."
            )
        }
        // Only approve/cancel cross the bridge; anything else fails closed as cancel.
        let decision: ConfirmationDecision = (input.decision == "approve") ? .approve : .cancel
        _ = await runtime.decide(token: token, decision: decision)
        // Clear the active confirmation in the UI; the command's own completion/cancel
        // is carried by the lifecycle event stream.
        emit(BridgeEventFactory.confirmationEvent(disclosure: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()))
        return ok(request, payload: DecideConfirmationResult(confirmationId: input.id, decision: input.decision))
    }

    /// Validates a settings patch against the deterministic allowlist (ADR-003) and
    /// persists an accepted patch through the settings store: unknown or
    /// policy-weakening keys are rejected before anything is saved, and a store
    /// failure is a structured error — `accepted` is never reported for a patch
    /// that did not become durable (FR-CFG-04).
    private func updateSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard
            let data = try? JSONEncoder().encode(request.payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let patch = object["patch"] as? [String: Any]
        else {
            return invalidInput(request, "updateSettings requires a patch.")
        }
        let changes = (patch["changes"] as? [String: Any]) ?? [:]
        let errors = SettingsPatchValidator.validate(changes: changes)
        guard errors.isEmpty else {
            return ok(request, payload: UpdateSettingsResult(accepted: false))
        }
        let settingsChanges = SettingsChanges(validatedChanges: changes)
        if let settingsStore {
            do {
                try settingsStore.apply(settingsChanges)
            } catch {
                return errorResponse(
                    request, category: .internalFailure,
                    code: "settings_not_saved",
                    message: "The settings change could not be saved."
                )
            }
            // Live policy re-arm (NIC-137): a change to "Ask before all actions" takes
            // effect immediately for the next command, not just on next launch.
            if let confirmAll = settingsChanges.confirmAllActions {
                runtime.updateConfirmAllActions(confirmAll)
            }
            // Let a settings-driven producer re-sample now (NIC-128): the Stocks producer
            // refreshes when the ticker list changes, so an edit is live at once rather than
            // on its next slow tick.
            onSettingsChanged?(settingsChanges)
            // Live cross-webview sync: every surface (dashboard + the separate native
            // settings window) reflects the new assistant name, mode colors, and motion
            // preference immediately, not just on next launch.
            emit(BridgeEventFactory.settingsChangedEvent(
                snapshot: resolvedSettingsSnapshot(),
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
        }
        return ok(request, payload: UpdateSettingsResult(accepted: true))
    }

    /// Reads the durable settings on demand so the settings UI initializes its
    /// controls from persisted state rather than hardcoded defaults (NIC-141). This
    /// is the read side of `updateSettings`; effective defaults are resolved in one
    /// deterministic place (``EffectiveSettings``).
    ///
    /// It never errors: a store load failure or a workspace-less host with no store
    /// bound (some tests) yields the effective defaults, mirroring how bootstrap
    /// degrades a missing stored default to the configured default mode. The
    /// configured default mode id is read through the same layered/shipped config
    /// path bootstrap uses — the "default mode" setting, distinct from the currently
    /// active mode.
    private func getSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: resolvedSettingsSnapshot())
    }

    /// The effective settings snapshot — the single resolution shared by `getSettings`
    /// (the read) and the `settings.changed` event (live sync after a write).
    private func resolvedSettingsSnapshot() -> CerebralHelmSettingsSnapshot {
        let stored = (try? settingsStore?.load()).flatMap { $0 } ?? StoredSettings()
        let configDefaultModeID: String?
        if let workspace {
            configDefaultModeID = BootstrapComposer.defaultModeID(workspace: workspace)
        } else {
            configDefaultModeID = BootstrapComposer.defaultModeID(configDirectory: configDirectory)
        }
        return EffectiveSettings.resolve(stored: stored, configDefaultModeID: configDefaultModeID)
    }

    /// The bootstrap state with mode restore applied (FR-MOD-05). This is the
    /// single composition every surface must use — the `getBootstrapState`
    /// operation and the shell's synchronous `window.__cerebralBootstrap`
    /// injection — so a restored mode can never differ by transport.
    public func composeBootstrapState() -> CerebralHelmBridgeBootstrapState {
        composeState(activeModeID: bootstrapModeID())
    }

    /// The mode bootstrap should activate: the last active mode when it still
    /// exists in config (FR-MOD-05 restart restore), else the stored default
    /// mode, else `nil` for the configured default. Stale references fall back,
    /// never error.
    private func bootstrapModeID() -> String? {
        if let store = modeStateStore,
           let lastActive = try? store.loadActiveModeID(),
           BootstrapComposer.modeExists(lastActive, configDirectory: configDirectory) {
            return lastActive
        }
        guard
            let store = settingsStore,
            let settings = try? store.load(),
            let stored = settings.defaultModeID,
            BootstrapComposer.modeExists(stored, configDirectory: configDirectory)
        else { return nil }
        return stored
    }

    // MARK: - Confirmation flow

    /// When a command pauses for confirmation, remember its single-use token and push
    /// the policy-owned disclosure to the dashboard as a `confirmation.changed` event.
    private func registerAwaitingConfirmation(_ outcome: CommandRuntimeOutcome) {
        guard case let .awaitingConfirmation(_, disclosure, token) = outcome else { return }
        tokenLock.lock()
        pendingTokens[token.confirmationID] = token
        tokenLock.unlock()
        emit(BridgeEventFactory.confirmationEvent(
            disclosure: disclosure, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func takeToken(id: String) -> ConfirmationToken? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return pendingTokens.removeValue(forKey: id)
    }

    private func emit(_ event: CerebralHelmBridgeEvent) {
        guard let data = try? BridgeMessageCoding.encoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        emitEventJSON(json)
    }

    // MARK: - Payload mapping

    private struct SubmitCommandInput: Decodable {
        let rawInput: String
        let source: String?
    }
    private struct CommandReceipt: Encodable {
        let commandId: String
        let accepted: Bool
    }
    private struct ApplyModeInput: Decodable {
        let modeId: String
    }
    private struct ApplyModeResult: Encodable {
        let modeId: String
        let status: String
    }
    private struct CaptureNoteInput: Decodable {
        let title: String
        let body: String
        let kind: String?
    }
    private struct CaptureNoteResult: Encodable {
        let noteId: String
    }
    private struct SearchNotesInput: Decodable {
        let text: String
        let limit: Int?
    }
    private struct NoteHit: Encodable {
        let noteId: String
        let title: String
        let excerpt: String
    }
    private struct SearchNotesResult: Encodable {
        let results: [NoteHit]
    }
    private struct DecideConfirmationInput: Decodable {
        let id: String
        let decision: String
    }
    private struct DecideConfirmationResult: Encodable {
        let confirmationId: String
        let decision: String
    }
    private struct UpdateSettingsResult: Encodable {
        let accepted: Bool
    }
    private struct DiscoveredApp: Encodable {
        let bundleId: String
        let name: String
        let iconPng: String?
        /// The configured app reference this bundle id backs (nil = not pinnable).
        let referenceId: String?
    }
    private struct ListAppsResult: Encodable {
        let apps: [DiscoveredApp]
        let truncated: Bool
    }
    private struct SpeedTestResult: Encodable {
        /// "ok" | "partial" | "unavailable" (mirrors the tool output).
        let status: String
        let downloadMbps: Double?
        let uploadMbps: Double?
        let testedAt: String?
    }
    private struct UpdateQuickAppsInput: Decodable {
        let modeId: String
        let quickApps: [String]
    }
    /// `{ reference, value }` — the `storeSecret` payload (NIC-134). `value` is the live secret;
    /// it is written to the Keychain and never echoed back or logged.
    private struct StoreSecretInput: Decodable {
        let reference: String
        let value: String
    }
    private struct StoreSecretResult: Encodable {
        let reference: String
        let stored: Bool
    }
    private struct SecretStatusInput: Decodable {
        let reference: String
    }
    /// Presence only — whether the reference is bound. Never carries the value (FR-CFG-03).
    private struct SecretStatusResult: Encodable {
        let reference: String
        let bound: Bool
    }
    /// `{ reference, deleted }` — the `deleteSecret` result (NIC-133). `deleted` is false when the
    /// reference was already absent (an idempotent no-op), true when a stored value was removed.
    private struct DeleteSecretResult: Encodable {
        let reference: String
        let deleted: Bool
    }
    /// `{ connected, scope? }` — the `connectSpotify` result (NIC-133). Reports success and the
    /// granted scope only; the OAuth tokens never cross the bridge (they live in the Keychain).
    private struct ConnectSpotifyResult: Encodable {
        let connected: Bool
        let scope: String?
    }
    private struct OpenLayoutInput: Decodable {
        let modeId: String
    }
    private struct OpenLayoutResult: Encodable {
        let accepted: Bool
        let modeId: String
    }
    private struct CloseLayoutResult: Encodable {
        let closed: Bool
    }
    private struct ToggleLayoutInput: Decodable {
        let ref: String
    }
    private struct ToggleLayoutResult: Encodable {
        let accepted: Bool
    }
    private struct PinLayoutWindowInput: Decodable {
        let modeId: String
        let ref: String
    }
    private struct PinLayoutWindowResult: Encodable {
        let accepted: Bool
        let errors: [String]
    }
    private struct AddLayoutTargetInput: Decodable {
        let ref: String
    }
    private struct AddLayoutTargetResult: Encodable {
        let accepted: Bool
    }
    private struct ToggleModeCollapseInput: Decodable {
        let modeId: String
    }
    private struct ToggleModeCollapseResult: Encodable {
        let collapsed: Bool
    }
    private struct WindowRefInput: Decodable {
        let windowId: String
    }
    private struct WindowActionResult: Encodable {
        let ok: Bool
    }
    private struct WindowDTO: Encodable {
        let id: String
        let title: String
        let minimized: Bool
    }
    private struct WindowGroupDTO: Encodable {
        let bundleId: String
        let appName: String
        let appIconPng: String?
        let windows: [WindowDTO]
    }
    private struct WindowInventory: Encodable {
        let apps: [WindowGroupDTO]
    }
    private struct UpdateLayoutInput: Decodable {
        let modeId: String
        let layout: [String: JSONAny]
    }
    private struct UpdateLayoutResult: Encodable {
        let accepted: Bool
        let errors: [String]
    }
    private struct CaptureWindow: Encodable {
        let ref: String
        let kind: String
        let frame: String
    }
    private struct CaptureLayoutResult: Encodable {
        let windows: [CaptureWindow]
    }
    private struct UpdateQuickAppsResult: Encodable {
        let accepted: Bool
        let quickApps: [String]
        let errors: [String]
    }
    private struct AddUrlReferenceInput: Decodable {
        let url: String
        let label: String?
        /// Optional Google Chrome profile directory (`--profile-directory`, NIC-151);
        /// when present the minted URL opens in that Chrome profile.
        let profile: String?
    }
    /// A configured URL reference, as delivered to the dashboard (NIC-146). `iconPng`
    /// is the site's cached favicon as base64 PNG (NIC-147), omitted when none is
    /// cached yet — the tile shows its placeholder glyph and upgrades live once the
    /// background fetch lands (`encodeIfPresent` drops the nil, mirroring app icons).
    private struct UrlReferenceDTO: Encodable {
        let id: String
        let label: String
        let target: String
        let iconPng: String?
        /// The reference's Chrome profile, when one is configured (NIC-151);
        /// `encodeIfPresent` omits it otherwise, so profile-less tiles are unchanged.
        let profile: String?
    }
    private struct AddUrlReferenceResult: Encodable {
        let accepted: Bool
        /// The minted (or already-existing) reference when accepted; nil on rejection.
        let reference: UrlReferenceDTO?
        let errors: [String]
    }
    private struct ListUrlsResult: Encodable {
        let urls: [UrlReferenceDTO]
    }
    /// A Chrome profile for the dropdown + avatar badges (NIC-151). `directory` is the
    /// `--profile-directory` value; `iconPng` is the account avatar, omitted when none.
    private struct ChromeProfileDTO: Encodable {
        let directory: String
        let name: String
        let iconPng: String?
    }
    private struct CalendarDTO: Encodable {
        let id: String
        let title: String
        let colorHex: String?
    }
    private struct CalendarsResult: Encodable {
        /// Whether Calendar access is granted; false → the UI shows "grant Calendar access".
        let authorized: Bool
        let calendars: [CalendarDTO]
    }
    private struct ChromeProfilesResult: Encodable {
        let profiles: [ChromeProfileDTO]
        /// The user's pinned Chrome-profile app references, so a pinned tile resolves
        /// its label + profile (and thence its avatar) without a separate feed.
        let references: [AppReferenceDTO]
    }
    private struct AddChromeProfileInput: Decodable {
        let directory: String
        let name: String?
    }
    /// A configured app reference (NIC-151): mirrors `UrlReferenceDTO` but for an app
    /// target (a bundle id). `profile` is the Chrome profile it opens in, when set.
    private struct AppReferenceDTO: Encodable {
        let id: String
        let label: String
        let target: String
        let profile: String?
    }
    private struct AddChromeProfileResult: Encodable {
        let accepted: Bool
        let reference: AppReferenceDTO?
        let errors: [String]
    }
    /// Mirrors the bridge `getRecentActivity` payload wrapper `{ recentActivity: … }`.
    private struct RecentActivityEnvelope: Encodable {
        let recentActivity = Activity()
        struct Activity: Encodable {
            let commands: [String] = []
            let toolCalls: [String] = []
            let confirmations: [String] = []
            let modeSessions: [String] = []
            let errors: [String] = []
        }
    }

    private func receipt(for outcome: CommandRuntimeOutcome) -> CommandReceipt {
        switch outcome {
        case let .completed(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case let .awaitingConfirmation(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case .rejected:
            return CommandReceipt(commandId: "", accepted: false)
        }
    }

    private func decodePayload<T: Decodable>(_ request: CerebralHelmBridgeOperationRequest) -> T? {
        guard let data = try? JSONEncoder().encode(request.payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodePayload<T: Encodable>(_ value: T) -> [String: JSONAny] {
        guard
            let data = try? JSONEncoder().encode(value),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }

    // MARK: - Responses

    private func ok<T: Encodable>(
        _ request: CerebralHelmBridgeOperationRequest, payload: T
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: nil,
            messageID: request.messageID,
            operation: request.operation,
            payload: encodePayload(payload),
            schemaVersion: messageSchemaVersion,
            status: .ok,
            type: .bridgeOperationResponse
        )
    }

    private func errorResponse(
        _ request: CerebralHelmBridgeOperationRequest,
        category: CerebralContracts.Category,
        code: String,
        message: String
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: CerebralHelmBridgeOperationResponseError(
                category: category, code: code, details: nil, message: message, remediation: nil
            ),
            messageID: request.messageID,
            operation: request.operation,
            payload: [:],
            schemaVersion: messageSchemaVersion,
            status: .error,
            type: .bridgeOperationResponse
        )
    }

    private func invalidInput(
        _ request: CerebralHelmBridgeOperationRequest, _ message: String
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(request, category: .invalidInput, code: "bridge_invalid_input", message: message)
    }

    private func unimplemented(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(
            request,
            category: .unavailableCapability,
            code: "bridge_operation_unimplemented",
            message: "This bridge operation is not wired to the runtime yet."
        )
    }
}
