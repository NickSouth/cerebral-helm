import AppKit
import WebKit
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import os

/// The per-mode layout editor window (NIC-142).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so the
/// layout editor — a substantial authoring surface — is its own floating, top-most
/// window rather than an in-backdrop overlay (the same backdrop-policy reasoning as the
/// settings and More Apps windows). It hosts `index.html?surface=layouteditor&mode=<id>`
/// over the **shared** `BridgeSession` (one runtime, multiple transports), so it captures
/// windows and writes the mode override through the same command bus as the dashboard.
///
/// Frameless like the settings window: the web surface draws its own themed × and title,
/// so the macOS title bar and traffic lights are hidden. Built fresh on each open (it is
/// mode-specific) and torn down on close; the × posts `closeLayoutEditor` so the
/// coordinator owns the window's lifecycle.
final class LayoutEditorWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let editorURL: URL
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "layouteditor")

    /// Web → native shell actions (closeLayoutEditor). Set by `WindowCoordinator`, which
    /// owns the action routing.
    var onShellControl: (([String: Any]) -> Void)?

    init(dashboardRoot: URL, session: BridgeSession, modeID: String) {
        handler = CerebralSchemeHandler(root: dashboardRoot)
        // The mode id is a config reference id (`^[a-z][a-z0-9-]*$`); percent-encode it
        // defensively before it enters the query string.
        let encoded = modeID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? modeID
        editorURL = URL(
            string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=layouteditor&mode=\(encoded)"
        )!

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme + modes + capabilities on first paint,
        // no loading flash) — composed by the session so the editor reads the same live
        // capabilities and mode labels as the dashboard.
        if let data = try? BridgeMessageCoding.encoder().encode(
            session.composeBootstrapState()
        ), let json = String(data: data, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__cerebralBootstrap = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        webView = WKWebView(frame: .zero, configuration: configuration)

        // A roomy editor window (a canvas + picker land in increments 5–6), centered.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit layout"
        // Frameless chrome: the web surface draws its own × (shellControl
        // `closeLayoutEditor`) and title, so the macOS title bar and traffic lights are
        // redundant. Hide them and let the content fill edge-to-edge.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Top-most so it sits in front of whatever the user is looking at — the backdrop
        // never lifts, so the editor must float above other apps.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = webView

        super.init()
        window.delegate = self
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: editorURL))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the editor re-gates / re-themes live if a
    /// capability flips while it's open.
    func deliverBridgeEvent(_ json: String) {
        bridge.deliverBridgeEvent(json)
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
        log.error("Layout editor surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Layout editor web content process terminated; reloading.")
        webView.load(URLRequest(url: editorURL))
    }
}
