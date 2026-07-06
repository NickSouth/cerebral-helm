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
/// `@unchecked Sendable`: window state is mutated only on the main thread — the
/// lifecycle entry points run from `AppDelegate` (main), and `deliverBridgeEvent`
/// re-dispatches itself to main before touching any state. The annotation exists so
/// the background event relay may hand `self` across the main-queue hop.
final class WindowCoordinator: @unchecked Sendable {
    private var dashboard: DashboardWindowController?
    private var palette: CommandPaletteWindowController?
    private var recovery: RecoveryWindowController?
    private var occlusionObserver: NSObjectProtocol?

    /// Fired on the main queue whenever the dashboard window becomes visible or
    /// fully occluded — the shell pauses the status publisher on hidden (NIC-81b).
    var onDashboardVisibilityChange: ((Bool) -> Void)?

    /// Ready path: host the dashboard and pre-warm the single command palette against the
    /// shared session. Called once after a clean startup pre-flight.
    func enterReady(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        let dashboard = DashboardWindowController(dashboardRoot: dashboardRoot, paths: paths, session: session)
        // Increment 4: web → native shell actions (e.g. rebinding the palette hotkey from
        // the settings "Hotkeys" panel).
        dashboard.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        self.dashboard = dashboard
        dashboard.show()

        // Visibility signal for the status publisher: a fully occluded or hidden
        // dashboard needs no live metric sampling (MAC-ADAPTER-3 battery AC).
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: dashboard.window,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.onDashboardVisibilityChange?(window.occlusionState.contains(.visible))
        }

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
        // Session/runtime events arrive on background tasks (BridgeSession executes
        // operations off-main), but confirmation surfacing below orders windows —
        // AppKit traps off the main thread (SIGTRAP in NSWindow orderOut). Hop once
        // at this seam so every downstream consumer is on main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.deliverBridgeEvent(json) }
            return
        }
        dashboard?.deliverBridgeEvent(json)
        if json.contains("\"config.changed\"") {
            palette?.deliverBridgeEvent(json)
        }
        // Increment 5: a pending confirmation must be seen in context (AC3). When a gated
        // command's disclosure arrives (e.g. one submitted from the palette) while the
        // dashboard may be backgrounded, surface the dashboard and dismiss the palette; the
        // neutral-blue confirmation renders in the dashboard's web overlay (design spec §9).
        // A `confirmation:null` payload is a *clear* (approved/cancelled) — not a new prompt.
        if json.contains("\"confirmation.changed\"") && !json.contains("\"confirmation\":null") {
            surfaceConfirmation()
        }
    }

    /// Summon (or refocus) the single command palette (FR-SHL-02/04). No-op in recovery.
    func summonPalette() {
        palette?.summon()
    }

    /// Open settings as the **web overlay** over the dashboard (NIC-76 / FR-UI-06): bring the
    /// dashboard forward and open the overlay via the shell-intent hook. There is no separate
    /// native settings window — settings never replaces the dashboard, and appears in context.
    func openSettings() {
        guard let dashboard else { return }
        dashboard.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboard.openSettings()
    }

    /// Increment 2: dismiss the palette (already done by its control channel), bring the
    /// dashboard forward, and open the conversation in the center panel with the text.
    private func routeAskHeimlich(_ text: String) {
        guard let dashboard else { return }
        dashboard.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboard.openConversation(text)
    }

    /// Increment 5: bring the dashboard forward (dismissing the palette) so a pending
    /// confirmation is always seen. No-op in recovery.
    private func surfaceConfirmation() {
        palette?.dismiss()
        guard let dashboard else { return }
        dashboard.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Increment 4: apply a web-driven shell action. Currently only the palette-hotkey
    /// rebind from the settings "Hotkeys" panel; the native shell owns the actual
    /// `KeyboardShortcuts` registration (a Mac-only concern kept off the portable bridge).
    private func handleShellControl(_ body: [String: Any]) {
        guard (body["action"] as? String) == "setPaletteShortcut",
              let presetID = body["preset"] as? String,
              let preset = PaletteShortcutPreset(rawValue: presetID) else { return }
        preset.apply()
    }
}
