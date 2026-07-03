import AppKit
import Foundation
import CerebralCore
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
final class WindowCoordinator {
    private var dashboard: DashboardWindowController?
    private var palette: CommandPaletteWindowController?
    private var settings: SettingsWindowController?
    private var recovery: RecoveryWindowController?

    /// Ready path: host the dashboard and pre-warm the single command palette against the
    /// shared session. Called once after a clean startup pre-flight.
    func enterReady(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        let dashboard = DashboardWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        self.dashboard = dashboard
        dashboard.show()

        let palette = CommandPaletteWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        // Increment 2: a conversational palette submission routes to the dashboard's
        // center-panel conversation rather than executing inline.
        palette.onAskHeimlich = { [weak self] text in self?.routeAskHeimlich(text) }
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
        dashboard?.deliverBridgeEvent(json)
        if json.contains("\"config.changed\"") {
            palette?.deliverBridgeEvent(json)
        }
    }

    /// Summon (or refocus) the single command palette (FR-SHL-02/04). No-op in recovery.
    func summonPalette() {
        palette?.summon()
    }

    /// Open the native settings window. (Reconciled to the web settings overlay in a later
    /// NIC-76 increment; kept here as the current owner for now.)
    func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.show()
    }

    /// Increment 2: dismiss the palette (already done by its control channel), bring the
    /// dashboard forward, and open the conversation in the center panel with the text.
    private func routeAskHeimlich(_ text: String) {
        guard let dashboard else { return }
        dashboard.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboard.openConversation(text)
    }
}
