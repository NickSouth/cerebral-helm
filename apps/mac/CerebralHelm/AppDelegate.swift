import AppKit
import CerebralCore

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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // the dashboard and the command-palette webview submit through it.
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

        // Hand the window roles to the coordinator (dashboard + pre-warmed palette).
        coordinator.enterReady(dashboardRoot: dashboardRoot, paths: paths, session: bridgeRuntime.session)

        // Route the shared session's event stream to the coordinator, which fans it to the
        // dashboard (and mode changes to the palette).
        bridgeRuntime.setEventSink { [weak self] json in
            self?.coordinator.deliverBridgeEvent(json)
        }

        // Live system metrics stream (NIC-81b): start once the sink is bound, and
        // pause sampling whenever the dashboard window is fully occluded.
        coordinator.onDashboardVisibilityChange = { [weak bridgeRuntime] visible in
            bridgeRuntime?.setStatusPublishingActive(visible)
        }
        bridgeRuntime.startStatusPublishing()

        // The menu-bar item + global summon hotkey (NIC-75 / FR-SHL-02). Both the menu
        // item and the hotkey drive the coordinator.
        menuBar = MenuBarController(
            summon: { [weak self] in self?.coordinator.summonPalette() },
            openSettings: { [weak self] in self?.coordinator.openSettings() }
        )
    }

    /// Permission recheck (NIC-83): the app becoming active is the moment a user
    /// returns from System Settings after changing a permission — re-derive the
    /// capability flags and announce any availability transition.
    func applicationDidBecomeActive(_ notification: Notification) {
        bridgeRuntime?.recheckPermissions()
    }
}
