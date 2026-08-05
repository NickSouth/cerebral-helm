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
    /// The left-edge sidebar panel: pre-warmed at launch and kept warm, so a summon is only a
    /// position + order-front. The global hotkey targets this (the palette is now reachable only
    /// from the menu bar, pending its removal).
    private var sidebar: SidebarWindowController?
    /// Watches the left screen edge and reveals the sidebar on a hover-dwell. Runs for the life
    /// of the ready session; an enable/disable setting is a follow-on increment.
    private let edgeMonitor = ScreenEdgeMonitor()
    private var recovery: RecoveryWindowController?
    private var confirmation: ConfirmationWindowController?
    /// The dedicated settings window (backdrop-policy decision): created lazily on
    /// first open, then reused warm. `nil` until then and always `nil` in recovery.
    private var settings: SettingsWindowController?
    /// The floating More Apps launcher window (NIC-148): built fresh on each open so
    /// the app list is current, and torn down on close. `nil` while closed.
    private var moreApps: MoreAppsWindowController?
    /// The transparent, top-most mode-swap dropdown (NIC-144): built fresh on each open,
    /// positioned above the bottom bar's mode control, dismissed on select / Escape /
    /// click-away. `nil` while closed.
    private var modeMenu: ModeMenuWindowController?
    /// The transparent, top-most layout hotswap "+" pin window (NIC-142): built fresh
    /// on each open, positioned above the bottom bar's "+", dismissed on × / Escape /
    /// click-away. `nil` while closed.
    private var layoutPin: LayoutPinWindowController?
    /// The per-mode layout editor window (NIC-142): built fresh on each open (it is
    /// mode-specific), torn down on close. `nil` while closed.
    private var layoutEditor: LayoutEditorWindowController?
    private var windowNavigator: WindowNavigatorWindowController?
    /// The expandable project detail window (NIC-129): built fresh on each open (its descriptor
    /// is re-read), torn down on close. `nil` while closed.
    private var projectDetail: ProjectDetailWindowController?
    /// One additional backdrop per connected non-main display (NIC-120b), keyed by
    /// the display's topology id. Created/removed by `reconcileBackdrops` on every
    /// topology change; each binds the SAME shared session (no second runtime).
    private var secondaries: [String: DashboardWindowController] = [:]
    private var dashboardRoot: URL?
    private var paths: WorkspacePaths?
    /// One occlusion observer per backdrop window, keyed by window identity —
    /// the status publisher pauses only when EVERY backdrop is invisible.
    private var occlusionObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    /// The reserved bottom-bar strip per backdrop window (NIC-144 inc 1), keyed by
    /// window identity. The dashboard reports its bar's on-screen rect over the
    /// shellControl channel; the coordinator converts it to an AppKit screen rect and
    /// caches the strip here. No consumer yet — the window-snap observer (inc 2) will
    /// read these to keep foreign windows above the bar.
    private var reservedStrips: [ObjectIdentifier: ReservedStrip] = [:]
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

    /// A live "Layout display" override from the settings surface (`setLayoutDisplay`,
    /// NIC-142), applied immediately; the durable value arrives via the settings patch
    /// and is read through `layoutDisplayIDProvider`.
    private var liveLayoutDisplayID: String?
    /// Reads the persisted "Layout display" id (NIC-142); wired by `AppDelegate`. nil /
    /// the sentinel / unknown / disconnected all degrade to the main display.
    var layoutDisplayIDProvider: (() -> String?)?

    /// Notified whenever the reserved bottom-bar strips change (NIC-142); wired by
    /// `AppDelegate` to feed the layout arrange so windows land above the bar.
    var onReservedStripsChanged: (([ReservedStrip]) -> Void)?
    /// The last non-null `layout.session.changed` JSON, replayed to the (possibly
    /// changed) layout-display surface when the setting or topology changes so the
    /// hotswap pill follows the chosen monitor (NIC-142). nil once the layout closes.
    private var lastLayoutSessionJSON: String?

    /// The login-item seam (NIC-89): the Startup panel toggles through it, and
    /// the OS's resulting status flows straight back — never a stored flag.
    var loginItem: (any LoginItemManaging) = SMAppServiceLoginItem()

    /// Fired on the main queue whenever backdrop visibility changes — the shell
    /// pauses the status publisher only when every backdrop is hidden (NIC-81b).
    var onDashboardVisibilityChange: ((Bool) -> Void)?
    /// Fired once a backdrop's bridge handshake proves the page can receive events, so the runtime
    /// can replay live widget state emitted while it was still loading.
    ///
    /// Fires for the main dashboard **and for every companion backdrop** (NIC-172). A companion is
    /// built fresh when a display is hot-plugged, long after the producers' events were sent, so it
    /// needs the same replay — the main dashboard's first handshake is not the only moment a surface
    /// appears. Replays are served from the producers' caches, so an extra call costs no fetch.
    var onDashboardBridgeReady: (() -> Void)?

    /// Ready path: host the dashboard and pre-warm the single command palette against the
    /// shared session. Called once after a clean startup pre-flight.
    func enterReady(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        self.session = session
        self.dashboardRoot = dashboardRoot
        self.paths = paths
        let dashboard = DashboardWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        // Increment 4: web → native shell actions (e.g. rebinding the palette hotkey from
        // the settings "Hotkeys" panel).
        dashboard.onShellControl = { [weak self, weak dashboard] body in
            self?.handleShellControl(body, from: dashboard)
        }
        // Runtime-only state that predates the web bridge is replayed once the
        // handshake proves the page can receive it (the initial topology event
        // always beats the webview's dynamic surface import).
        dashboard.onBridgeReady = { [weak self, weak dashboard] in
            // Live widget state whose first emit can also beat the page's import (news, served
            // from a warm cache) is replayed through the runtime, which re-emits from cache
            // rather than re-fetching — no provider quota is spent to repaint a panel.
            self?.onDashboardBridgeReady?()
            guard let json = self?.lastTopologyJSON else { return }
            dashboard?.deliverBridgeEvent(json)
        }
        self.dashboard = dashboard
        dashboard.show()

        // Visibility signal for the status publisher: sampling pauses only when
        // every backdrop is fully occluded or hidden (MAC-ADAPTER-3 battery AC).
        observeOcclusion(of: dashboard.window)

        // The edge sidebar shares the same session and the same shell-action routing as the
        // dashboard, so quick-app pinning and More Apps behave identically from the column.
        let sidebar = SidebarWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        sidebar.onShellControl = { [weak self] body in self?.handleShellControl(body, from: nil) }
        // The sidebar attaches to the desktop's leftmost edge, not the main display.
        sidebar.targetScreen = { [weak self] in self?.leftmostScreen() }
        // A Report/Input quick action run from the column opens on the dashboard instead. The
        // sidebar has already dismissed itself and stowed the covering windows by this point.
        sidebar.onRevealDashboard = { [weak self] report, input in
            guard let dashboard = self?.dashboard else { return }
            if let report { dashboard.openReport(report) }
            if let input { dashboard.openInput(input) }
        }
        self.sidebar = sidebar

        // Hover-dwell at that same edge reveals it (owner decision, 2026-08-03). The monitor stays
        // suppressed while the sidebar is already out.
        edgeMonitor.targetScreen = { [weak self] in self?.leftmostScreen() }
        edgeMonitor.isSuppressed = { [weak self] in self?.sidebar?.isVisible ?? false }
        // A hover reveal does NOT focus the command input: the user reached for the sidebar with
        // the pointer, and an autofocused box popping open a suggestion list reads as noise. The
        // hotkey path focuses, because there the user is already typing.
        edgeMonitor.onTrigger = { [weak self] in self?.sidebar?.summon(from: .edge) }
        // A hover-revealed column collapses when the pointer leaves it (standard flyout behavior).
        // `hoverFrame` returns nil when the sidebar is pinned or was summoned by the hotkey, which
        // is what keeps those two cases open.
        edgeMonitor.hoverFrame = { [weak self] in self?.sidebar?.hoverFrame }
        edgeMonitor.onExit = { [weak self] in self?.sidebar?.dismiss() }
        applySidebarEdgePreference()
        edgeMonitor.start()
    }

    /// Recovery path: a single read-only recovery window; no dashboard or palette exist.
    func enterRecovery(_ recovery: Bootstrap.Recovery) {
        let controller = RecoveryWindowController(recovery)
        self.recovery = controller
        controller.show()
    }

    /// The reserved bottom-bar strips currently known (NIC-144), one per reporting
    /// backdrop. The window-snap observer reads these on every settle to keep foreign
    /// windows above the bar; an empty result (no report yet) means no correction.
    func currentReservedStrips() -> [ReservedStrip] {
        Array(reservedStrips.values)
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
        // The layout hotswap pill shows on the layout-display monitor only (NIC-142):
        // deliver the session to that surface and a null session to every other
        // bottom-bar surface. Handled here so no other surface ever sees it.
        if json.contains("\"layout.session.changed\"") {
            lastLayoutSessionJSON = json.contains("\"session\":null") ? nil : json
            fanOutLayoutSession()
            return
        }
        dashboard?.deliverBridgeEvent(json)
        // The sidebar renders the same live widgets as the dashboard, so it takes the full event
        // stream — not the palette's mode-only subset.
        sidebar?.deliverBridgeEvent(json)
        for secondary in secondaries.values {
            secondary.deliverBridgeEvent(json)
        }
        settings?.deliverBridgeEvent(json)
        moreApps?.deliverBridgeEvent(json)
        layoutPin?.deliverBridgeEvent(json)
        layoutEditor?.deliverBridgeEvent(json)
        windowNavigator?.deliverBridgeEvent(json)
        projectDetail?.deliverBridgeEvent(json)
        if json.contains("\"config.changed\"") {
            // Keep the open dropdown's active-mode highlight and theme current if the mode
            // changes from elsewhere while it's open (NIC-144).
            modeMenu?.deliverBridgeEvent(json)
        }
    }

    /// Toggle the left-edge sidebar and focus its command input — the global hotkey's target.
    /// No-op in recovery, where no sidebar exists.
    func toggleSidebar() {
        sidebar?.toggle()
    }

    /// Push the persisted edge-reveal preference into the live monitor. Called at startup and
    /// after every settings change, so a toggle or a dwell change applies without a restart.
    private func applySidebarEdgePreference() {
        edgeMonitor.isEnabled = SidebarEdgePreference.isEnabled
        edgeMonitor.dwell = SidebarEdgePreference.dwell.seconds
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
            secondary.onShellControl = { [weak self, weak secondary] body in
                self?.handleShellControl(body, from: secondary)
            }
            secondary.onBridgeReady = { [weak self, weak secondary] in
                // A companion appears mid-session, so it has missed every event already sent —
                // including the weather that the bootstrap does not carry (NIC-172). Replay before
                // the topology so it lands in the same order the main dashboard sees.
                self?.onDashboardBridgeReady?()
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
            // Its bar is gone with the display — drop the reserved strip so the
            // window-snap observer stops honoring a bar that no longer exists (NIC-144).
            reservedStrips[ObjectIdentifier(window)] = nil
            onReservedStripsChanged?(Array(reservedStrips.values))
            // Every reconcile path hops to main first (deliverBridgeEvent /
            // handleDisplayTopologyChange / script-message handlers), but the
            // compiler cannot see that through the closure chain — assert it.
            MainActor.assumeIsolated {
                window.orderOut(nil)
            }
        }
        secondaries = kept
        publishBackdropVisibility()
        // A display appeared/disappeared: re-route the hotswap pill so it stays on the
        // layout display (or moves to the main backdrop if the layout display went
        // away), and clear it from any new companion (NIC-142).
        fanOutLayoutSession()
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

    /// The display layout mode opens on and whose bottom bar shows the hotswap pill
    /// (NIC-142): the live override else the persisted setting, when it names a
    /// still-connected stable-identity display; the sentinel / unset / unknown /
    /// disconnected all degrade to the main display.
    private func layoutDescriptor(
        in topology: BridgeEventFactory.DisplayTopologyPayload
    ) -> BridgeEventFactory.DisplayDescriptor? {
        let requested = liveLayoutDisplayID ?? layoutDisplayIDProvider?()
        if let requested, requested != "system-primary",
           let match = topology.displays.first(where: { $0.id == requested && $0.stableIdentity }) {
            return match
        }
        return mainDescriptor(in: topology)
    }

    /// The bottom-bar surface on the layout display — the main backdrop when the
    /// layout display is the main display, else the companion on that display (nil
    /// when it has no live surface, e.g. a transient reconcile).
    private func layoutDisplaySurface() -> DashboardWindowController? {
        guard let topology = lastTopology, let layout = layoutDescriptor(in: topology) else {
            return dashboard
        }
        if let main = mainDescriptor(in: topology), main.id == layout.id {
            return dashboard
        }
        return secondaries[layout.id]
    }

    /// Deliver the current layout session only to the layout-display surface; every
    /// other bottom-bar surface gets a null session so its hotswap pill clears (NIC-142).
    /// Re-run when the setting or topology changes so the pill follows the monitor.
    private func fanOutLayoutSession() {
        let target = layoutDisplaySurface()
        let session = lastLayoutSessionJSON ?? Self.nullLayoutSessionJSON
        if let dashboard {
            dashboard.deliverBridgeEvent(dashboard === target ? session : Self.nullLayoutSessionJSON)
        }
        for secondary in secondaries.values {
            secondary.deliverBridgeEvent(secondary === target ? session : Self.nullLayoutSessionJSON)
        }
    }

    /// A layout-session-ended event, delivered to non-layout-display surfaces so their
    /// hotswap pill never appears (NIC-142). The web reducer folds `payload.session`.
    private static let nullLayoutSessionJSON =
        #"{"schemaVersion":"1.0.0","type":"layout.session.changed","eventId":"brevt_layoutdisplaynull00","timestamp":"1970-01-01T00:00:00.000Z","payload":{"session":null}}"#

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

    /// The display holding the leftmost edge of the whole desktop — where the sidebar lives
    /// regardless of which display is "main" (owner decision, 2026-08-03).
    ///
    /// This is the only edge that is a genuine wall rather than a crossing point between monitors,
    /// so it is both where the column should attach and the only edge the hover trigger can arm
    /// without firing every time the pointer travels between displays. Recomputed per call, so a
    /// display being plugged in or rearranged moves the sidebar with no extra bookkeeping.
    private func leftmostScreen() -> NSScreen? {
        NSScreen.screens.min { $0.frame.minX < $1.frame.minX }
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
    ///
    /// `anchor` is the More Apps button's rect in the dashboard webview's viewport
    /// (from `getBoundingClientRect`); the backdrop fills the screen frame, so it
    /// converts to screen coordinates through the dashboard window and the launcher
    /// drops directly under the button. Absent anchor degrades to a right-edge open.
    func openMoreApps(anchor: [String: Any]? = nil) {
        guard let session, let dashboardRoot else { return }
        moreApps?.close()
        let controller = MoreAppsWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        moreApps = controller
        let screen = dashboard?.window.screen ?? mainScreen() ?? NSScreen.main
        if let anchor, let dashboardWindow = dashboard?.window,
           let anchorRect = Self.anchorScreenRect(anchor, in: dashboardWindow), let screen {
            controller.positionUnder(anchorRect, on: screen)
        } else if let screen {
            controller.positionOnRight(of: screen)
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Convert a viewport rect `{x,y,width,height}` (web CSS px, y-down from the
    /// top-left) into an AppKit screen rect (y-up). The borderless backdrop fills
    /// the screen frame with the webview as its whole content view, so the webview
    /// origin is the window's top-left corner.
    private static func anchorScreenRect(_ anchor: [String: Any], in window: NSWindow) -> NSRect? {
        guard
            let x = anchor["x"] as? Double, let y = anchor["y"] as? Double,
            let w = anchor["width"] as? Double, let h = anchor["height"] as? Double
        else { return nil }
        let frame = window.frame
        return NSRect(x: frame.minX + x, y: frame.maxY - y - h, width: w, height: h)
    }

    /// Close and release the More Apps window — the × control, Escape, or an
    /// accepted app launch all post `closeMoreApps` (dismiss-on-open, NIC-148).
    func closeMoreApps() {
        moreApps?.close()
        moreApps = nil
    }

    /// Open the window navigator (NIC-143): a top-most floating window listing every
    /// open window for quick surface/minimize/close. Built fresh each open (any existing
    /// one is replaced) so its inventory is current, and placed toward the right edge.
    func openWindowNavigator() {
        guard let session, let dashboardRoot else { return }
        windowNavigator?.close()
        let controller = WindowNavigatorWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        windowNavigator = controller
        if let screen = dashboard?.window.screen ?? mainScreen() ?? NSScreen.main {
            controller.positionOnRight(of: screen)
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the navigator — the × control, Escape, or an accepted surface
    /// all post `closeWindowNavigator` (dismiss-on-surface, NIC-143).
    func closeWindowNavigator() {
        windowNavigator?.close()
        windowNavigator = nil
    }

    /// Open the expandable project detail window (NIC-129): reads the clicked project's
    /// `PROJECT.md` (constrained to the projects root) and renders it in its own window with a
    /// placeholder live-status section. Built fresh each open (any existing one is replaced) so
    /// the descriptor is current. A no-op in recovery, or when the project has no readable
    /// descriptor — Increment 6 disables the row in that case, so the click shouldn't fire.
    func openProjectDetail(path: String) {
        guard let session, let dashboardRoot else { return }
        guard let descriptor = ProjectDescriptor.read(projectPath: path) else { return }
        projectDetail?.close()
        let controller = ProjectDetailWindowController(
            dashboardRoot: dashboardRoot, session: session, projectPath: path,
            name: descriptor.name, markdownBody: descriptor.body,
            importance: descriptor.importance ?? 0
        )
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        projectDetail = controller
        if let screen = dashboard?.window.screen ?? mainScreen() ?? NSScreen.main {
            controller.positionCentered(on: screen)
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the project detail window — the × control posts `closeProjectDetail`.
    func closeProjectDetail() {
        projectDetail?.close()
        projectDetail = nil
    }

    /// Persist a new `importance` for a project (NIC-129): the detail window's priority stepper
    /// posts each change, and this writes it into the project's `PROJECT.md` frontmatter
    /// (constrained to the projects root, floored at 0). The `projects` widget reorders on its
    /// producer's next scan; the stepper already updated its own number optimistically.
    func setProjectImportance(path: String, importance: Int) {
        ProjectImportanceWriter.write(projectPath: path, importance: importance)
    }

    /// Open the transparent mode-swap dropdown above the bottom bar's mode control
    /// (NIC-144). Built fresh each open (any existing one is replaced) so its active-mode
    /// highlight is current — a transient menu, not a warm panel. `anchor` is the mode
    /// trigger's rect in the reporting webview's viewport; the backdrop fills the screen
    /// frame, so it converts through that window and the dropdown drops directly above the
    /// control. Absent anchor degrades to a bottom-center open. No-op in recovery.
    func openModeMenu(anchor: [String: Any]? = nil, from source: DashboardWindowController? = nil) {
        guard let session, let dashboardRoot else { return }
        modeMenu?.close()
        let controller = ModeMenuWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        modeMenu = controller
        let anchorWindow = source?.window ?? dashboard?.window
        let screen = anchorWindow?.screen ?? mainScreen() ?? NSScreen.main
        if let anchor, let anchorWindow,
           let anchorRect = Self.anchorScreenRect(anchor, in: anchorWindow), let screen {
            controller.positionAbove(anchorRect, on: screen)
        } else if let screen {
            controller.positionBottomCenter(on: screen)
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the mode dropdown — a selection, Escape, or click-away all post
    /// `closeModeMenu` (or the window resigning key routes here).
    func closeModeMenu() {
        modeMenu?.close()
        modeMenu = nil
    }

    /// Open the transparent, top-most layout hotswap "+" pin window above the bottom
    /// bar's "+" (NIC-142). Built fresh each open (any existing one is replaced) so its
    /// app discovery is current — a transient picker, not a warm panel. `anchor` is the
    /// "+" button's rect in the reporting webview's viewport; the backdrop fills the
    /// screen frame, so it converts through that window and the picker drops directly
    /// above the "+". Absent anchor degrades to a bottom-left open. No-op in recovery.
    func openLayoutPin(anchor: [String: Any]? = nil, from source: DashboardWindowController? = nil) {
        guard let session, let dashboardRoot else { return }
        layoutPin?.close()
        let controller = LayoutPinWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        layoutPin = controller
        let anchorWindow = source?.window ?? dashboard?.window
        let screen = anchorWindow?.screen ?? mainScreen() ?? NSScreen.main
        if let anchor, let anchorWindow,
           let anchorRect = Self.anchorScreenRect(anchor, in: anchorWindow), let screen {
            controller.positionAbove(anchorRect, on: screen)
        } else if let screen {
            controller.positionBottomLeft(on: screen)
        }
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the layout-pin window — the ×, Escape, or click-away all post
    /// `closeLayoutPin` (or the window resigning key routes here).
    func closeLayoutPin() {
        layoutPin?.close()
        layoutPin = nil
    }

    /// Open the per-mode layout editor window (NIC-142). Built fresh each open (any open
    /// one is replaced) so it edits the requested mode. Centered, frameless, top-most.
    /// No-op in recovery or without a mode id.
    func openLayoutEditor(modeID: String) {
        guard let session, let dashboardRoot, !modeID.isEmpty else { return }
        layoutEditor?.close()
        let controller = LayoutEditorWindowController(
            dashboardRoot: dashboardRoot, session: session, modeID: modeID
        )
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        layoutEditor = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close and release the layout editor window — its × posts `closeLayoutEditor`.
    func closeLayoutEditor() {
        layoutEditor?.close()
        layoutEditor = nil
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
    private func handleShellControl(_ body: [String: Any], from source: DashboardWindowController? = nil) {
        switch body["action"] as? String {
        case "setPaletteShortcut":
            guard let presetID = body["preset"] as? String,
                  let preset = PaletteShortcutPreset(rawValue: presetID) else { return }
            preset.apply()
        case "setSidebarEdge":
            // Both fields are optional so the panel can change either control independently.
            // An unrecognized dwell id is ignored rather than defaulted, so a malformed message
            // can never silently retune a setting the user did not touch.
            if let enabled = body["enabled"] as? Bool {
                SidebarEdgePreference.isEnabled = enabled
            }
            if let dwellID = body["dwell"] as? String,
               let dwell = SidebarEdgePreference.Dwell(rawValue: dwellID) {
                SidebarEdgePreference.dwell = dwell
            }
            applySidebarEdgePreference()
        case "openSettings":
            openSettings()
        case "closeSettings":
            settings?.close()
        case "openMoreApps":
            openMoreApps(anchor: body["anchor"] as? [String: Any])
        case "closeMoreApps":
            closeMoreApps()
        case "openWindowNavigator":
            openWindowNavigator()
        case "closeWindowNavigator":
            closeWindowNavigator()
        case "openProjectDetail":
            guard let path = body["path"] as? String else { return }
            openProjectDetail(path: path)
        case "closeProjectDetail":
            closeProjectDetail()
        case "setProjectImportance":
            guard let path = body["path"] as? String,
                  let importance = body["importance"] as? Int else { return }
            setProjectImportance(path: path, importance: importance)
        case "openModeMenu":
            openModeMenu(anchor: body["anchor"] as? [String: Any], from: source)
        case "closeModeMenu":
            closeModeMenu()
        case "openLayoutPin":
            openLayoutPin(anchor: body["anchor"] as? [String: Any], from: source)
        case "closeLayoutPin":
            closeLayoutPin()
        case "openLayoutEditor":
            guard let modeID = body["modeId"] as? String else { return }
            openLayoutEditor(modeID: modeID)
        case "closeLayoutEditor":
            closeLayoutEditor()
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
        case "setLayoutDisplay":
            // Live re-target (NIC-142): the durable value already went through the
            // validated settings patch; this moves the hotswap pill to the chosen
            // monitor's bottom bar without a restart. (The layout arrange reads the
            // persisted value at the next open.)
            guard let id = body["id"] as? String else { return }
            liveLayoutDisplayID = id
            fanOutLayoutSession()
        case "pickKnowledgeRoot":
            presentKnowledgeRootPicker()
        case "browseKnowledgeRoot":
            browseKnowledgeRoot()
        case "reportBottomBarRect":
            updateReservedStrip(body, from: source)
        default:
            return
        }
    }

    /// NIC-144 inc 1: the dashboard reports its bottom bar's on-screen rect (web CSS
    /// viewport px, from `getBoundingClientRect`) on layout and on resize. Convert it
    /// to an AppKit screen rect against the reporting backdrop's window — the borderless
    /// backdrop fills the screen frame, so `anchorScreenRect` maps the viewport straight
    /// to screen coordinates — and cache the reserved strip (the bar's band plus a
    /// symmetric gap above it). A re-fit to another display re-sizes the webview, which
    /// fires a web resize and re-reports, so a moved backdrop self-heals. Only the main
    /// dashboard reports a source today; companion secondaries follow in inc 3.
    private func updateReservedStrip(_ body: [String: Any], from source: DashboardWindowController?) {
        guard
            let source,
            let rect = body["rect"] as? [String: Any],
            let barFrame = Self.anchorScreenRect(rect, in: source.window),
            let screen = source.window.screen
        else { return }
        reservedStrips[ObjectIdentifier(source.window)] = ReservedStrip.from(
            barFrame: barFrame, screenFrame: screen.frame
        )
        onReservedStripsChanged?(Array(reservedStrips.values))
    }

    /// NIC-162: open the knowledge root in Obsidian — the browsing surface for
    /// durable notes.
    ///
    /// The notes are plain Markdown that Obsidian reads far better than a settings
    /// panel could, so CerebralHelm hands off rather than reimplementing a reader.
    /// Without Obsidian installed the folder is revealed in Finder instead: the
    /// action still does something real, and the panel is told which happened so it
    /// can say so. Nothing is written either way — this only opens what exists.
    private func browseKnowledgeRoot() {
        MainActor.assumeIsolated {
            guard let paths, let root = try? makeKnowledgeService(paths).rootPath else {
                settings?.pushNotesBrowserOutcome("unavailable")
                return
            }
            let rootURL = URL(fileURLWithPath: root)
            // A root that was never created (or was moved away) is not something to
            // open — say so instead of handing Obsidian a path that does not exist.
            guard FileManager.default.fileExists(atPath: rootURL.path) else {
                settings?.pushNotesBrowserOutcome("missing-root")
                return
            }

            switch ObsidianLink.destination(forRoot: rootURL, obsidianInstalled: Self.obsidianInstalled) {
            case let .obsidian(url):
                NSWorkspace.shared.open(url)
                // Obsidian opens, but only if the folder is already one of its
                // vaults — the URI cannot register a new one, and there is no way
                // to detect that from here. The panel carries the one-time hint.
                settings?.pushNotesBrowserOutcome("obsidian")
            case let .revealInFinder(url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                settings?.pushNotesBrowserOutcome("finder")
            }
        }
    }

    /// Whether anything on this Mac handles `obsidian://`. Resolved per call rather
    /// than cached: the user may install Obsidian while the app is running.
    static var obsidianInstalled: Bool {
        guard let probe = URL(string: "obsidian://open") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
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
