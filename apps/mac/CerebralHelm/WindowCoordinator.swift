import AppKit
import Foundation
import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost

/// The single owner of the shell's native window roles (NIC-76 / FR-SHL-04): the
/// dashboard window, the floating command-palette panel, the settings window, and the
/// read-only recovery window.
///
/// Centralizing ownership here gives each role exactly one owner with deterministic
/// show/hide/focus/z-order/placement and a clean shutdown — no duplicate or orphan
/// windows (AC1). The runtime/bridge (`AppBridgeRuntime`) and the menu-bar item
/// (`MenuBarController`) are separate concerns owned by `AppDelegate`; this type is the
/// window-management seam only. Ready and recovery are mutually exclusive: a recovery
/// launch has no dashboard or palette.
/// `@unchecked Sendable`: window state is mutated only on the main thread — the
/// lifecycle entry points run from `AppDelegate` (main), and `deliverBridgeEvent`
/// re-dispatches itself to main before touching any state. The annotation exists so
/// the background event relay may hand `self` across the main-queue hop.
final class WindowCoordinator: @unchecked Sendable {
    private var dashboard: DashboardWindowController?
    private var palette: CommandPaletteWindowController?
    private var recovery: RecoveryWindowController?
    private var confirmation: ConfirmationWindowController?
    /// The dedicated settings window (backdrop-policy decision): created lazily on
    /// first open, then reused warm. `nil` until then and always `nil` in recovery.
    private var settings: SettingsWindowController?
    /// The floating More Apps launcher window (NIC-148): built fresh on each open so
    /// the app list is current, and torn down on close. `nil` while closed.
    private var moreApps: MoreAppsWindowController?
    /// One additional backdrop per connected non-main display (NIC-120b), keyed by
    /// the display's topology id. Created/removed by `reconcileBackdrops` on every
    /// topology change; each binds the SAME shared session (no second runtime).
    private var secondaries: [String: DashboardWindowController] = [:]
    private var dashboardRoot: URL?
    private var paths: WorkspacePaths?
    /// One occlusion observer per backdrop window, keyed by window identity —
    /// the status publisher pauses only when EVERY backdrop is invisible.
    private var occlusionObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    /// The shared bridge session — the confirmation panel submits its
    /// approve/cancel decision through the same versioned operation the
    /// dashboard uses (`decideConfirmation`), never a side channel.
    private var session: BridgeSession?
    /// The last topology the observer reported, plus its encoded event JSON —
    /// replayed into webviews created (or loaded) after the event fired, since
    /// topology is runtime-only state and never part of the bootstrap.
    private var lastTopology: BridgeEventFactory.DisplayTopologyPayload?
    private var lastTopologyJSON: String?
    /// A live main-display override from the settings surface (`setMainDisplay`),
    /// applied immediately; the durable value arrives via the settings patch and
    /// is read through `mainDisplayIDProvider` on the next launch.
    private var liveMainDisplayID: String?

    /// Reads the persisted "Main display" id (NIC-120b); wired by `AppDelegate`
    /// to the runtime's settings store. nil / unknown / disconnected ids all
    /// degrade to the system primary display.
    var mainDisplayIDProvider: (() -> String?)?

    /// The login-item seam (NIC-89): the Startup panel toggles through it, and
    /// the OS's resulting status flows straight back — never a stored flag.
    var loginItem: (any LoginItemManaging) = SMAppServiceLoginItem()

    /// Fired on the main queue whenever backdrop visibility changes — the shell
    /// pauses the status publisher only when every backdrop is hidden (NIC-81b).
    var onDashboardVisibilityChange: ((Bool) -> Void)?

    /// Ready path: host the dashboard and pre-warm the single command palette against the
    /// shared session. Called once after a clean startup pre-flight.
    func enterReady(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        self.session = session
        self.dashboardRoot = dashboardRoot
        self.paths = paths
        let dashboard = DashboardWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        // Increment 4: web → native shell actions (e.g. rebinding the palette hotkey from
        // the settings "Hotkeys" panel).
        dashboard.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        // Runtime-only state that predates the web bridge is replayed once the
        // handshake proves the page can receive it (the initial topology event
        // always beats the webview's dynamic surface import).
        dashboard.onBridgeReady = { [weak self, weak dashboard] in
            guard let json = self?.lastTopologyJSON else { return }
            dashboard?.deliverBridgeEvent(json)
        }
        self.dashboard = dashboard
        dashboard.show()

        // Visibility signal for the status publisher: sampling pauses only when
        // every backdrop is fully occluded or hidden (MAC-ADAPTER-3 battery AC).
        observeOcclusion(of: dashboard.window)

        let palette = CommandPaletteWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        // A palette submission routes to the dashboard's command bus (NIC-124) rather than
        // opening a conversation (which no longer exists).
        palette.onAskHeimlich = { [weak self] text in self?.routeAskHeimlich(text) }
        // Palette focus targets the main display (NIC-120b), not whichever screen
        // has keyboard focus.
        palette.targetScreen = { [weak self] in self?.mainScreen() }
        self.palette = palette
    }

    /// Recovery path: a single read-only recovery window; no dashboard or palette exist.
    func enterRecovery(_ recovery: Bootstrap.Recovery) {
        let controller = RecoveryWindowController(recovery)
        self.recovery = controller
        controller.show()
    }

    /// Route a shared-session event to the dashboard webview. Mode changes
    /// (`config.changed`) are additionally forwarded to the palette so it re-themes to the
    /// active mode (Increment 3); everything else is dashboard-only.
    func deliverBridgeEvent(_ json: String) {
        // Session/runtime events arrive on background tasks (BridgeSession executes
        // operations off-main), but confirmation surfacing below orders windows —
        // AppKit traps off the main thread (SIGTRAP in NSWindow orderOut). Hop once
        // at this seam so every downstream consumer is on main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.deliverBridgeEvent(json) }
            return
        }
        // A pending confirmation must be seen (NIC-76 AC3). The dashboard is a strict
        // backdrop and never lifts (backdrop-policy decision, 2026-07-06), so the
        // disclosure renders ONLY on its own floating panel — the dashboard webview
        // never receives confirmation events (no duplicate in-backdrop overlay).
        // `confirmation:null` (approved, cancelled, or expired) closes the panel.
        if json.contains("\"confirmation.changed\"") {
            handleConfirmationEvent(json)
            return
        }
        // Topology is runtime-only state: cache the latest snapshot so webviews
        // created (or finishing load) after this event can be brought current.
        if json.contains("\"display.topology.changed\"") {
            lastTopologyJSON = json
        }
        dashboard?.deliverBridgeEvent(json)
        for secondary in secondaries.values {
            secondary.deliverBridgeEvent(json)
        }
        settings?.deliverBridgeEvent(json)
        moreApps?.deliverBridgeEvent(json)
        if json.contains("\"config.changed\"") {
            palette?.deliverBridgeEvent(json)
        }
    }

    /// Summon (or refocus) the single command palette (FR-SHL-02/04). No-op in recovery.
    func summonPalette() {
        palette?.summon()
    }

    /// Display topology changed (NIC-87/120b): reconcile one backdrop per
    /// connected display — the main backdrop on the chosen main display (persisted
    /// setting, degrading to the system primary), a secondary on every other
    /// display, none left behind for disconnected ones. The recovery window is
    /// re-hosted onto a live screen when no screen shows it; the palette needs
    /// nothing — `summon()` re-positions onto the main display every time.
    func handleDisplayTopologyChange(_ topology: BridgeEventFactory.DisplayTopologyPayload) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleDisplayTopologyChange(topology) }
            return
        }
        lastTopology = topology
        reconcileBackdrops(topology)
        rehostIfStranded(recovery?.window)
    }

    /// One backdrop per display (NIC-120b AC). A transitional zero-display
    /// topology changes nothing — the next event re-reconciles.
    private func reconcileBackdrops(_ topology: BridgeEventFactory.DisplayTopologyPayload) {
        guard let dashboard, !topology.displays.isEmpty else { return }
        let main = mainDescriptor(in: topology)
        if let main, let mainScreen = screen(for: main) {
            dashboard.fit(to: mainScreen)
        }

        var kept: [String: DashboardWindowController] = [:]
        for descriptor in topology.displays where descriptor.id != main?.id {
            guard let target = screen(for: descriptor) else { continue }
            if let existing = secondaries[descriptor.id] {
                existing.fit(to: target)
                kept[descriptor.id] = existing
                continue
            }
            guard let session, let dashboardRoot, let paths else { continue }
            // Secondaries host the reduced companion surface (owner decision,
            // 2026-07-06): the Heimlich stream + bottom bar only — no command
            // bar or quick actions off the main display.
            let secondary = DashboardWindowController(
                dashboardRoot: dashboardRoot, paths: paths, session: session, screen: target, surface: .companion
            )
            secondary.onShellControl = { [weak self] body in self?.handleShellControl(body) }
            secondary.onBridgeReady = { [weak self, weak secondary] in
                guard let json = self?.lastTopologyJSON else { return }
                secondary?.deliverBridgeEvent(json)
            }
            observeOcclusion(of: secondary.window)
            secondary.showWithoutFocus()
            kept[descriptor.id] = secondary
        }
        for (id, controller) in secondaries where kept[id] == nil {
            let window = controller.window
            stopObservingOcclusion(of: window)
            // Every reconcile path hops to main first (deliverBridgeEvent /
            // handleDisplayTopologyChange / script-message handlers), but the
            // compiler cannot see that through the closure chain — assert it.
            MainActor.assumeIsolated {
                window.orderOut(nil)
            }
        }
        secondaries = kept
        publishBackdropVisibility()
    }

    /// The display the main backdrop (and palette focus) belongs on:
    /// the live settings override, else the persisted setting — either only when
    /// it names a still-connected, stable-identity display — else the system
    /// primary. Stale or unknown ids degrade silently, never error (NIC-87 AC).
    private func mainDescriptor(
        in topology: BridgeEventFactory.DisplayTopologyPayload
    ) -> BridgeEventFactory.DisplayDescriptor? {
        let requested = liveMainDisplayID ?? mainDisplayIDProvider?()
        if let requested, requested != "system-primary",
           let match = topology.displays.first(where: { $0.id == requested && $0.stableIdentity }) {
            return match
        }
        return topology.displays.first(where: \.primary) ?? topology.displays.first
    }

    /// Resolve a topology descriptor to its live `NSScreen` by frame — both sides
    /// were read from the same screen list, so frames match exactly; a race with
    /// a mid-flight display change simply misses and the next event re-reconciles.
    private func screen(for descriptor: BridgeEventFactory.DisplayDescriptor) -> NSScreen? {
        let frame = NSRect(
            x: descriptor.frame.x, y: descriptor.frame.y,
            width: descriptor.frame.width, height: descriptor.frame.height
        )
        return NSScreen.screens.first { $0.frame == frame }
    }

    /// The screen currently hosting the main backdrop (palette targeting).
    private func mainScreen() -> NSScreen? {
        guard let topology = lastTopology, let main = mainDescriptor(in: topology) else { return nil }
        return screen(for: main)
    }

    // MARK: - Backdrop visibility (status-publisher pause, NIC-81b)

    private func observeOcclusion(of window: NSWindow) {
        occlusionObservers[ObjectIdentifier(window)] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.publishBackdropVisibility()
        }
    }

    private func stopObservingOcclusion(of window: NSWindow) {
        if let observer = occlusionObservers.removeValue(forKey: ObjectIdentifier(window)) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Live metrics keep sampling while ANY backdrop is visible; they pause only
    /// when every backdrop is hidden or fully covered.
    private func publishBackdropVisibility() {
        var windows: [NSWindow] = []
        if let dashboard { windows.append(dashboard.window) }
        windows.append(contentsOf: secondaries.values.map(\.window))
        guard !windows.isEmpty else { return }
        onDashboardVisibilityChange?(windows.contains { $0.occlusionState.contains(.visible) })
    }

    /// Re-center a window on the main screen when no connected screen's visible
    /// frame intersects it. A transitional zero-screen topology (clamshell mid-
    /// switch) changes nothing — the next topology event re-checks.
    private func rehostIfStranded(_ window: NSWindow?) {
        guard let window else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { return }
        let target = (NSScreen.main ?? screens[0]).visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, target.width)
        frame.size.height = min(frame.height, target.height)
        frame.origin.x = target.midX - frame.width / 2
        frame.origin.y = target.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }

    /// Open the dedicated settings window (backdrop-policy decision, 2026-07-06;
    /// reverses NIC-76's overlay-only presentation — the overlay remains for
    /// browser previews without a native shell).
    func openSettings() {
        // The dedicated normal-level settings window (backdrop-policy decision):
        // the dashboard never lifts, so settings is a real window that can sit
        // above other apps. No-op in recovery (no session/bundle).
        guard let session, let dashboardRoot else { return }
        let controller = settings ?? SettingsWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        // The "Main display" select needs the current topology (runtime-only
        // state this lazily-created webview missed).
        controller.onBridgeReady = { [weak self, weak controller] in
            guard let json = self?.lastTopologyJSON else { return }
            controller?.deliverBridgeEvent(json)
        }
        settings = controller
        controller.show()
        // A reused warm window seeds status only at creation; the user can flip
        // the login item in System Settings while we run — push the live truth.
        controller.pushLoginItemStatus(loginItem.status().rawValue)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Open the floating More Apps launcher window (NIC-148). Built fresh each time
    /// (any open one is replaced) so its app list and capabilities are current — it
    /// is a transient launcher, not a warm-reused panel. No-op in recovery.
    func openMoreApps() {
        guard let session, let dashboardRoot else { return }
        moreApps?.close()
        let controller = MoreAppsWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        moreApps = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the More Apps window — the × control, Escape, or an
    /// accepted app launch all post `closeMoreApps` (dismiss-on-open, NIC-148).
    func closeMoreApps() {
        moreApps?.close()
        moreApps = nil
    }

    /// Dismiss the palette (already done by its control channel), bring the dashboard forward,
    /// and dispatch the submitted text through the dashboard's command bus. The Heimlich chat
    /// was removed (NIC-124): a command's result surfaces in the dashboard status line, and an
    /// unrecognized command reports the honest not-implemented state — no conversation opens.
    private func routeAskHeimlich(_ text: String) {
        guard let dashboard else { return }
        // The dashboard is the backdrop and may be covered by other apps; its surfacing UX is
        // deliberately deferred (backdrop-policy decision, 2026-07-06); do not lift it.
        NSApp.activate(ignoringOtherApps: true)
        dashboard.submitCommand(text)
    }

    /// Present or clear the dedicated confirmation panel from one
    /// `confirmation.changed` event. The panel and the dashboard's web overlay
    /// render the same policy-owned disclosure; a decision on either surface
    /// clears both through the runtime's `confirmation:null` event.
    private func handleConfirmationEvent(_ json: String) {
        guard
            let event = try? CerebralHelmBridgeEvent(data: Data(json.utf8)),
            event.type == .confirmationChanged
        else { return }
        guard
            let confirmationPayload = event.payload["confirmation"],
            let data = try? JSONEncoder().encode(confirmationPayload),
            let disclosure = try? CerebralHelmConfirmationDisclosure(data: data)
        else {
            // Resolved or invalidated — this surface goes away.
            confirmation?.close()
            confirmation = nil
            return
        }
        palette?.dismiss()
        let controller = ConfirmationWindowController(disclosure: disclosure) { [weak self] id, decision in
            self?.decideConfirmation(id: id, decision: decision)
        }
        confirmation = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Submit the panel's decision as the versioned `decideConfirmation`
    /// operation on the shared session — identical semantics to the dashboard
    /// overlay deciding. The resulting `confirmation:null` event closes the panel.
    private func decideConfirmation(id: String, decision: String) {
        guard let session else { return }
        struct DecisionPayload: Encodable {
            let id: String
            let decision: String
        }
        struct RequestEnvelope: Encodable {
            let schemaVersion = "1.0.0"
            let messageId: String
            let type = "bridge.operation.request"
            let operation = "decideConfirmation"
            let payload: DecisionPayload
        }
        let envelope = RequestEnvelope(
            messageId: "brmsg_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            payload: DecisionPayload(id: id, decision: decision)
        )
        guard
            let data = try? JSONEncoder().encode(envelope),
            let request = try? CerebralHelmBridgeOperationRequest(data: data)
        else { return }
        Task { _ = await session.execute(request) }
    }

    /// Apply a web-driven shell action (NIC-76 increment 4, extended by the
    /// backdrop-policy decision and NIC-148): the palette-hotkey rebind from the
    /// settings "Hotkeys" panel, opening/closing the dedicated settings window (the
    /// dashboard gear posts `openSettings`; the settings surface's × posts
    /// `closeSettings`), and opening/closing the floating More Apps launcher (the
    /// More Apps tile posts `openMoreApps`; its ×, Escape, or an accepted launch
    /// post `closeMoreApps`). Window control is a Mac-only concern kept off the
    /// portable bridge.
    private func handleShellControl(_ body: [String: Any]) {
        switch body["action"] as? String {
        case "setPaletteShortcut":
            guard let presetID = body["preset"] as? String,
                  let preset = PaletteShortcutPreset(rawValue: presetID) else { return }
            preset.apply()
        case "openSettings":
            openSettings()
        case "closeSettings":
            settings?.close()
        case "openMoreApps":
            openMoreApps()
        case "closeMoreApps":
            closeMoreApps()
        case "setLoginItem":
            // Launch-at-login toggle (NIC-89): register/unregister via the
            // SMAppService seam and push the OS's resulting status back to the
            // panel — including requires-approval, which the panel explains.
            guard let enabled = body["enabled"] as? Bool else { return }
            let status = (try? loginItem.setEnabled(enabled)) ?? loginItem.status()
            settings?.pushLoginItemStatus(status.rawValue)
        case "setMainDisplay":
            // Live re-host (NIC-120b): the durable value already went through the
            // validated settings patch; this applies it without a restart. Stored
            // verbatim — "system-primary" must override a stale persisted id too.
            guard let id = body["id"] as? String else { return }
            liveMainDisplayID = id
            if let topology = lastTopology {
                reconcileBackdrops(topology)
            }
        case "pickKnowledgeRoot":
            presentKnowledgeRootPicker()
        default:
            return
        }
    }

    /// NIC-138: choose the durable-knowledge root folder through a native directory
    /// picker, then hand the chosen path back to the Setup panel, which persists it
    /// through the validated settings patch. Presented as a sheet on the settings
    /// window when one exists. Selection only re-points where knowledge lives; it never
    /// moves or deletes anything at the old or new location (that is the knowledge
    /// system's durable-state contract, honored when it consumes the setting).
    private func presentKnowledgeRootPicker() {
        // handleShellControl is delivered on the main thread (WKScriptMessageHandler),
        // and NSOpenPanel + its sheet/modal completion are main-actor bound, so the whole
        // picker is safely assume-isolated to the main actor.
        MainActor.assumeIsolated {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose"
            panel.message = "Choose the folder where CerebralHelm keeps your durable knowledge."
            let deliver: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                MainActor.assumeIsolated {
                    guard response == .OK, let url = panel.url else { return }
                    self?.settings?.pushKnowledgeRoot(url.path)
                }
            }
            if let window = settings?.window {
                panel.beginSheetModal(for: window, completionHandler: deliver)
            } else {
                deliver(panel.runModal())
            }
        }
    }
}
