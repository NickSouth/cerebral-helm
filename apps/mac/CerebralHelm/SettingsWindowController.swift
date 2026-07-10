import AppKit
import WebKit
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import os

/// The dedicated native settings window (backdrop-policy decision, 2026-07-06).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so
/// settings — which must be usable while other apps are open — is a real
/// normal-level window rather than the retired in-backdrop web overlay (reverses
/// NIC-76's overlay-only presentation; the overlay remains for browser previews).
/// It hosts the same bundle at `index.html?surface=settings` over the **shared**
/// `BridgeSession` (the palette pattern: one runtime, multiple transports), so
/// panels read modes, capabilities, and settings identically to the dashboard.
///
/// Built lazily on first open and reused; closing hides it (the webview stays
/// warm). The web layer's `shellControl` channel posts `closeSettings` (the ×
/// control) and `setPaletteShortcut` (Hotkeys panel) — routed to the coordinator.
final class SettingsWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "settings")

    /// Web → native shell actions (closeSettings, setPaletteShortcut,
    /// setMainDisplay). Set by `WindowCoordinator`, which owns the action routing.
    var onShellControl: (([String: Any]) -> Void)?

    /// Fired when this webview's bridge completes its handshake — the earliest
    /// moment events can be received (`didFinish` is too early: the surface
    /// module loads via dynamic import afterwards). The coordinator replays the
    /// cached display topology so the "Main display" select is populated.
    var onBridgeReady: (() -> Void)?

    private static var settingsURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=settings")!
    }

    init(dashboardRoot: URL, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme + modes + capabilities on first
        // paint, no loading flash) — composed by the session so the restored mode
        // applies here exactly as on the dashboard (FR-MOD-05).
        if let data = try? BridgeMessageCoding.encoder().encode(
            session.composeBootstrapState()
        ), let json = String(data: data, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__cerebralBootstrap = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // Seed the Hotkeys panel with the current palette shortcut (NIC-76).
        let preset = PaletteShortcutPreset.current
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__cerebralHotkey = { preset: \"\(preset.rawValue)\", label: \"\(preset.label)\" };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        // Seed the Startup panel with the LIVE login-item status (NIC-89): the OS
        // is the source of truth — the settings store never carries this flag.
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__cerebralLoginItem = { status: \"\(SMAppServiceLoginItem().status().rawValue)\" };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        webView = WKWebView(frame: .zero, configuration: configuration)

        // Sized to the web surface's design dimensions (design spec §10); resizable
        // so long panels are usable, min-bounded so the two-pane layout never crushes.
        // Slightly shorter than the old 620 (NIC-140) now that the macOS title bar is gone.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm Settings"
        window.minSize = NSSize(width: 640, height: 440)
        // Frameless chrome (NIC-140): the web surface draws its own × (shellControl
        // `closeSettings`) and section titles, so the macOS title bar and traffic
        // lights are redundant. Hide them and let the content fill edge-to-edge —
        // the same frameless treatment as the command palette. The window stays
        // draggable from any non-interactive background via movableByWindowBackground;
        // the web layer reserves a top drag strip so nothing interactive sits under it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Closing hides the reusable window; the controller keeps owning it.
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = webView

        super.init()
        window.delegate = self
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        bridge.attach(to: webView)
        bridge.bind(session: session)
        bridge.onHandshake = { [weak self] in self?.onBridgeReady?() }
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Self.settingsURL))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event (config/capability changes re-theme and
    /// re-gate the panels live). The coordinator decides which events arrive here.
    func deliverBridgeEvent(_ json: String) {
        bridge.deliverBridgeEvent(json)
    }

    /// Push the current login-item status into the Startup panel (NIC-89): after
    /// a toggle, and on every reopen of this warm window — the document-start
    /// seed only reflects creation time, and the user can flip the login item in
    /// System Settings while we run.
    func pushLoginItemStatus(_ status: String) {
        webView.evaluateJavaScript(
            "window.__cerebralLoginItemUpdate && window.__cerebralLoginItemUpdate(\"\(status)\");"
        )
    }

    /// Push the folder chosen in the native NSOpenPanel picker into the Setup panel
    /// (NIC-138); the panel persists it through the validated settings patch. The path
    /// is escaped for the JS string literal so spaces, quotes, and backslashes survive.
    func pushKnowledgeRoot(_ path: String) {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            "window.__cerebralKnowledgeRootUpdate && window.__cerebralKnowledgeRootUpdate(\"\(escaped)\");"
        )
    }

    // MARK: - WKScriptMessageHandler (web → native shell control)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == DashboardWindowController.controlHandlerName,
            let body = message.body as? [String: Any]
        else { return }
        onShellControl?(body)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Settings surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    /// WebKit killed the content process (hidden-window reclaim, memory pressure).
    /// Reload so the window never shows the dead-renderer artifact.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Settings web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.settingsURL))
    }
}
