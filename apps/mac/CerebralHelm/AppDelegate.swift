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

        let controller = DashboardWindowController(dashboardRoot: dashboardRoot, paths: paths)
        controller.show()
        dashboardWindow = controller
    }

    private func enterRecovery(_ recovery: Bootstrap.Recovery) {
        let controller = RecoveryWindowController(recovery)
        controller.show()
        recoveryWindow = controller
    }
}
