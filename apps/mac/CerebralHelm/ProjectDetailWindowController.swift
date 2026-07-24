import AppKit
import WebKit
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import os

/// The expandable project detail window (NIC-129).
///
/// Clicking a project in the Executive `projects` widget opens its `PROJECT.md` here (the
/// ticket's "expands into a window"). Like the More Apps / navigator / settings windows, it is
/// its own `NSWindow` rather than an in-backdrop overlay — the dashboard is a strict backdrop
/// that never lifts, so a reading pane the user interacts with must be a real window. It hosts
/// `index.html?surface=projectdetail` over the **shared** `BridgeSession` (so it themes and
/// re-themes with everything else) and carries the per-project markdown as its own
/// `window.__cerebralProjectDetail` global, keeping the shared bootstrap contract free of
/// per-project fields.
///
/// Frameless: the web surface draws its own themed × and title. Built fresh on each open (the
/// descriptor is re-read) and torn down on close.
final class ProjectDetailWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "projectdetail")

    /// Web → native shell actions (closeProjectDetail). Set by `WindowCoordinator`.
    var onShellControl: (([String: Any]) -> Void)?

    private static var detailURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=projectdetail")!
    }

    init(dashboardRoot: URL, session: BridgeSession, projectPath: String, name: String, markdownBody: String, importance: Int) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the shared bootstrap synchronously (theme on first paint, no loading flash).
        if let data = try? BridgeMessageCoding.encoder().encode(session.composeBootstrapState()),
           let json = String(data: data, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__cerebralBootstrap = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // The per-project payload rides alongside the shared bootstrap as its own global,
        // JSON-encoded so the name/body/path are safely escaped into the injected script. It
        // carries `path` and `importance` so the priority stepper can write the new value back.
        let payload: [String: Any] = [
            "path": projectPath, "name": name, "markdownBody": markdownBody, "importance": importance
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let json = String(data: data, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__cerebralProjectDetail = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        webView = WKWebView(frame: .zero, configuration: configuration)

        // A reading pane — wider than the navigator, comfortable for prose. Normal level
        // (like the settings window): it sits above the sub-normal backdrop but does not need
        // to float over other apps the way the navigator does.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
        webView.load(URLRequest(url: Self.detailURL))
    }

    /// Center the window on `screen`.
    func positionCentered(on screen: NSScreen) {
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the detail window re-themes live while open.
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
        log.error("Project detail surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Project detail web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.detailURL))
    }
}
