import AppKit
import Foundation
import CerebralContracts
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
    private var confirmation: ConfirmationWindowController?
    /// The dedicated settings window (backdrop-policy decision): created lazily on
    /// first open, then reused warm. `nil` until then and always `nil` in recovery.
    private var settings: SettingsWindowController?
    private var dashboardRoot: URL?
    private var occlusionObserver: NSObjectProtocol?
    /// The shared bridge session — the confirmation panel submits its
    /// approve/cancel decision through the same versioned operation the
    /// dashboard uses (`decideConfirmation`), never a side channel.
    private var session: BridgeSession?

    /// Fired on the main queue whenever the dashboard window becomes visible or
    /// fully occluded — the shell pauses the status publisher on hidden (NIC-81b).
    var onDashboardVisibilityChange: ((Bool) -> Void)?

    /// Ready path: host the dashboard and pre-warm the single command palette against the
    /// shared session. Called once after a clean startup pre-flight.
    func enterReady(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        self.session = session
        self.dashboardRoot = dashboardRoot
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
        // A pending confirmation must be seen (NIC-76 AC3). The dashboard is a strict
        // backdrop and never lifts (backdrop-policy decision, 2026-07-06), so the
        // disclosure renders ONLY on its own floating panel — the dashboard webview
        // never receives confirmation events (no duplicate in-backdrop overlay).
        // `confirmation:null` (approved, cancelled, or expired) closes the panel.
        if json.contains("\"confirmation.changed\"") {
            handleConfirmationEvent(json)
            return
        }
        dashboard?.deliverBridgeEvent(json)
        settings?.deliverBridgeEvent(json)
        if json.contains("\"config.changed\"") {
            palette?.deliverBridgeEvent(json)
        }
    }

    /// Summon (or refocus) the single command palette (FR-SHL-02/04). No-op in recovery.
    func summonPalette() {
        palette?.summon()
    }

    /// Display topology changed (NIC-87): a disconnect must not strand critical
    /// windows. The dashboard backdrop re-fits to the current primary screen
    /// (NIC-120a); the recovery window is re-hosted onto a live screen when no
    /// screen shows it; the palette needs nothing — `summon()` re-positions it
    /// against the current main screen every time.
    func handleDisplayTopologyChange() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handleDisplayTopologyChange() }
            return
        }
        dashboard?.fitToPrimaryScreen()
        rehostIfStranded(recovery?.window)
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

    /// Open settings as the **web overlay** over the dashboard (NIC-76 / FR-UI-06): bring the
    /// dashboard forward and open the overlay via the shell-intent hook. There is no separate
    /// native settings window — settings never replaces the dashboard, and appears in context.
    func openSettings() {
        // The dedicated normal-level settings window (backdrop-policy decision):
        // the dashboard never lifts, so settings is a real window that can sit
        // above other apps. No-op in recovery (no session/bundle).
        guard let session, let dashboardRoot else { return }
        let controller = settings ?? SettingsWindowController(dashboardRoot: dashboardRoot, session: session)
        controller.onShellControl = { [weak self] body in self?.handleShellControl(body) }
        settings = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Increment 2: dismiss the palette (already done by its control channel), bring the
    /// dashboard forward, and open the conversation in the center panel with the text.
    private func routeAskHeimlich(_ text: String) {
        guard let dashboard else { return }
        // The conversation opens in the backdrop's center panel and may be
        // covered by other apps — its surfacing UX is deliberately deferred
        // (backdrop-policy decision, 2026-07-06); do not lift the dashboard.
        NSApp.activate(ignoringOtherApps: true)
        dashboard.openConversation(text)
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
    /// backdrop-policy decision): the palette-hotkey rebind from the settings
    /// "Hotkeys" panel, plus opening/closing the dedicated settings window (the
    /// dashboard gear posts `openSettings`; the settings surface's × posts
    /// `closeSettings`). Window control is a Mac-only concern kept off the
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
        default:
            return
        }
    }
}
