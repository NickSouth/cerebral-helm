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
    private var dashboardWindow: DashboardWindowController?
    private var recoveryWindow: RecoveryWindowController?
    private var menuBar: MenuBarController?
    private var bridgeRuntime: AppBridgeRuntime?
    private var paletteWindow: CommandPaletteWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch Bootstrap.run() {
        case let .ready(paths):
            enterReady(paths)
        case let .recovery(recovery):
            enterRecovery(recovery)
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
            enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "state_root_uncreatable",
                remediation: "Grant write access to ~/Library/Application Support, then relaunch.",
                details: ["Could not create the state root at \(paths.stateRoot.path): \(error)"]
            ))
            return
        }

        guard let dashboardRoot = DashboardWindowController.bundledDashboardRoot() else {
            enterRecovery(Bootstrap.Recovery(
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
            enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "runtime_composition_failed",
                remediation: "Reinstall CerebralHelm; the command runtime could not be composed.",
                details: ["makeCommandRuntime failed after a clean startup pre-flight."]
            ))
            return
        }
        self.bridgeRuntime = bridgeRuntime

        let controller = DashboardWindowController(
            dashboardRoot: dashboardRoot, paths: paths, session: bridgeRuntime.session
        )
        controller.show()
        dashboardWindow = controller

        // Route the shared session's event stream (lifecycle/confirmation/config) to the
        // dashboard webview — the palette only submits, so it is not an event sink.
        bridgeRuntime.setEventSink { [weak self] json in
            chProbe("sink self=\(self == nil ? "NIL" : "ok") dash=\(self?.dashboardWindow == nil ? "NIL" : "ok")") // TEMP
            self?.dashboardWindow?.deliverBridgeEvent(json)
        }

        // Pre-warm the command palette so the hotkey/menu summon it instantly (NIC-75 /
        // FR-SHL-02 latency target). One controller ⇒ one panel ⇒ no duplicate palettes.
        paletteWindow = CommandPaletteWindowController(
            dashboardRoot: dashboardRoot, paths: paths, session: bridgeRuntime.session
        )

        // The menu-bar item + global summon hotkey (NIC-75 / FR-SHL-02). Both the menu
        // item and the hotkey call `summonPalette`.
        menuBar = MenuBarController(
            summon: { [weak self] in self?.summonPalette() },
            openSettings: { [weak self] in self?.openSettings() }
        )
    }

    /// Summon (or refocus) the one command palette (FR-SHL-02).
    private func summonPalette() {
        paletteWindow?.summon()
    }

    /// Open the native settings window (hosts the hotkey recorder + remediation).
    private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show()
    }

    private func enterRecovery(_ recovery: Bootstrap.Recovery) {
        let controller = RecoveryWindowController(recovery)
        controller.show()
        recoveryWindow = controller
    }
}
