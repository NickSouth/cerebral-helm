import AppKit
import CerebralCore
import CerebralMacAdapters

/// The macOS application lifecycle owner (NIC-72 / FR-SHL-01, FR-SHL-05; NIC-73 / FR-SHL-03).
///
/// On launch the shell runs a read-only startup pre-flight (`Bootstrap.run`) that
/// validates data paths, the bundled config schemas, and the operational database
/// *before any write*. A clean pre-flight creates the writable state root and hosts
/// the bundled production dashboard in a `WKWebView` (offline); a failed pre-flight —
/// or a missing dashboard bundle — opens the read-only recovery window and mutates
/// nothing (PRD §8.1). The native bridge transport follows in NIC-74; until then the
/// dashboard runs against its in-webview mock bridge.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The single owner of native window roles (NIC-76). AppDelegate keeps only the
    /// non-window concerns: the live runtime/bridge and the menu-bar item.
    private let coordinator = WindowCoordinator()
    private var menuBar: MenuBarController?
    private var bridgeRuntime: AppBridgeRuntime?
    /// Keeps other apps' windows off the persistent bottom bar (NIC-144). Reads the
    /// coordinator's live reserved strips; inert until Accessibility is trusted.
    private var windowSnap: WindowSnapObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard (NIC-89): a duplicate launch — e.g. the login
        // item firing while the app is already open — focuses the existing
        // instance and exits BEFORE the startup pre-flight, so two processes
        // never race the same operational database.
        if let existing = SingleInstanceGuard.existingInstance(bundleID: Bundle.main.bundleIdentifier) {
            existing.activate()
            NSApp.terminate(nil)
            return
        }
        // Install the main menu (esp. the Edit menu) so the standard editing
        // shortcuts — ⌘V paste into the URL pin field / command bar / settings —
        // reach the hosted WKWebView. Without an Edit menu macOS never routes them.
        MainMenu.install(appName: "CerebralHelm")
        switch Bootstrap.run() {
        case let .ready(paths):
            enterReady(paths)
        case let .recovery(recovery):
            coordinator.enterRecovery(recovery)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A clean pre-flight: create the writable state root (the first legitimate
    /// write), then host the bundled dashboard. If the state root cannot be created
    /// or the dashboard bundle is missing, fall back to a visible diagnostic rather
    /// than run over a broken state or show a blank window.
    private func enterReady(_ paths: WorkspacePaths) {
        do {
            try FileManager.default.createDirectory(
                at: paths.stateRoot, withIntermediateDirectories: true
            )
        } catch {
            coordinator.enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "state_root_uncreatable",
                remediation: "Grant write access to ~/Library/Application Support, then relaunch.",
                details: ["Could not create the state root at \(paths.stateRoot.path): \(error)"]
            ))
            return
        }

        guard let dashboardRoot = DashboardWindowController.bundledDashboardRoot() else {
            coordinator.enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "dashboard_bundle_missing",
                remediation: "Build the dashboard bundle (apps/mac/scripts/build-dashboard-bundle.sh), then rebuild the app.",
                details: ["The bundled dashboard (Resources/DashboardBundle/index.html) was not found in this build."]
            ))
            return
        }

        // The single live runtime + bridge session for this app session (NIC-75). Both
        // the dashboard and the sidebar webview submit through it.
        guard let bridgeRuntime = AppBridgeRuntime(paths: paths) else {
            coordinator.enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "runtime_composition_failed",
                remediation: "Reinstall CerebralHelm; the command runtime could not be composed.",
                details: ["makeCommandRuntime failed after a clean startup pre-flight."]
            ))
            return
        }
        self.bridgeRuntime = bridgeRuntime

        // Hand the window roles to the coordinator (dashboard + pre-warmed sidebar).
        coordinator.enterReady(dashboardRoot: dashboardRoot, paths: paths, session: bridgeRuntime.session)

        // Route the shared session's event stream to the coordinator, which fans it to the
        // dashboard and the sidebar.
        bridgeRuntime.setEventSink { [weak self] json in
            self?.coordinator.deliverBridgeEvent(json)
        }

        // Live system metrics stream (NIC-81b): start once the sink is bound, and
        // pause sampling whenever the dashboard window is fully occluded.
        coordinator.onDashboardVisibilityChange = { [weak bridgeRuntime] visible in
            bridgeRuntime?.setStatusPublishingActive(visible)
        }
        // Assigned before the publishers start, so a handshake that lands early still replays.
        coordinator.onDashboardBridgeReady = { [weak bridgeRuntime] in
            bridgeRuntime?.resendLiveWidgetState()
        }
        bridgeRuntime.startStatusPublishing()

        // Display detection (NIC-87/120b): the initial topology snapshot publishes
        // now (the sink is bound), and every hot-plug transition reconciles the
        // per-display backdrops before the dashboard is told the topology changed.
        // The persisted "Main display" choice is read through the runtime until a
        // settings-read bridge operation exists.
        coordinator.mainDisplayIDProvider = { [weak bridgeRuntime] in
            bridgeRuntime?.storedMainDisplayID()
        }
        // The persisted "Layout display" choice (NIC-142), read through the runtime
        // until a settings-read bridge operation exists.
        coordinator.layoutDisplayIDProvider = { [weak bridgeRuntime] in
            bridgeRuntime?.storedLayoutDisplayID()
        }
        // Feed the reserved bottom-bar strips to the layout arrange so windows land above
        // the bar the first time, not after the snap observer nudges them (NIC-142).
        coordinator.onReservedStripsChanged = { [weak bridgeRuntime] strips in
            bridgeRuntime?.setReservedStrips(strips)
        }
        bridgeRuntime.startDisplayObservation { [weak self] topology in
            self?.coordinator.handleDisplayTopologyChange(topology)
        }

        // Window-snap awareness of the bottom bar (NIC-144): keep other apps' windows
        // above the reserved strip the coordinator caches from the bar's live rect.
        // Inert without Accessibility trust — never a prompt (FR-SAF-07); a later grant
        // takes effect on the next observation start.
        let windowSnap = WindowSnapObserver(
            surface: SystemWindowSnapSurface(),
            reservedStrips: { [weak self] in self?.coordinator.currentReservedStrips() ?? [] }
        )
        windowSnap.start()
        self.windowSnap = windowSnap

        // The menu-bar item + global summon hotkey (NIC-75 / FR-SHL-02). Both drive the sidebar,
        // which replaced the command palette as the app's command surface.
        menuBar = MenuBarController(
            summonSidebar: { [weak self] in self?.coordinator.toggleSidebar() },
            openSettings: { [weak self] in self?.coordinator.openSettings() }
        )
    }

    /// Permission recheck (NIC-83): the app becoming active is the moment a user
    /// returns from System Settings after changing a permission — re-derive the
    /// capability flags and announce any availability transition.
    func applicationDidBecomeActive(_ notification: Notification) {
        bridgeRuntime?.recheckPermissions()
        // The same return-from-System-Settings moment may have granted Accessibility —
        // re-arm window-snap observation (idempotent once armed), so it starts working
        // without a relaunch (NIC-144).
        windowSnap?.start()
    }
}
