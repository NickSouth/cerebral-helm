import AppKit
import WebKit
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import os

/// The window-navigator window (NIC-143).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so the
/// navigator — which must sit in front of, and act on, whatever windows the user has
/// open — is its own **floating**, top-most window rather than an in-backdrop overlay
/// that could be covered (the same backdrop-policy reasoning as the More Apps and
/// settings windows). It hosts `index.html?surface=windownavigator` over the **shared**
/// `BridgeSession`, so its list/minimize/surface/close calls reach the same live
/// Accessibility capability as everything else on the command bus.
///
/// Frameless like the More Apps window: the web surface draws its own themed × and
/// title, so the macOS title bar and traffic lights are hidden. Built fresh on each
/// open (not reused warm) so the window inventory is current, and torn down on close.
final class WindowNavigatorWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "windownavigator")

    /// Web → native shell actions (closeWindowNavigator). Set by `WindowCoordinator`.
    var onShellControl: (([String: Any]) -> Void)?

    /// Kept in step with `.win-nav__scrim + .win-nav`'s `min(264px, 92vw)` in `shell.css`.
    private static let contentWidth: CGFloat = 264
    /// Kept in step with `.win-nav`'s `border-radius: 26px`.
    private static let slabCornerRadius: CGFloat = 26

    private static var navigatorURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=windownavigator")!
    }

    init(dashboardRoot: URL, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme on first paint, no loading flash),
        // composed by the shared session.
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
        VibrantWindowChrome.makeTransparent(webView)

        // A tall, narrow panel (the iPhone-switcher feel): a single column of windows,
        // scroll for more. **264 is the web surface's width, not a guess** — the slab halved
        // (owner, 2026-08-07) because a narrow column is what makes the list read as a wheel
        // rather than a wall, and a window wider than the surface it hosts would give that
        // back as dead margin.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Open windows"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Top-most so it sits in front of the windows it navigates — the backdrop never
        // lifts, so the navigator must float above other apps.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        // The slab draws its own tint and curvature; the vibrancy behind it supplies the blur that
        // CSS cannot reach past the webview. `slabCornerRadius` is the single authority for the
        // corner — the standalone web surface deliberately leaves its own radius at 0 so the two
        // cannot drift apart.
        VibrantWindowChrome.apply(
            to: window,
            hosting: webView,
            cornerRadius: Self.slabCornerRadius
        )

        super.init()
        window.delegate = self
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Self.navigatorURL))
    }

    /// Place the navigator toward the right edge of the screen, vertically centered and
    /// clear of the edge — the "cards flowing up the right side" placement.
    func positionOnRight(of screen: NSScreen) {
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        var frame = window.frame
        frame.origin.x = visible.maxX - frame.width - margin
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrame(frame, display: true)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the navigator re-themes live while open.
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
        log.error("Window navigator surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Window navigator web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.navigatorURL))
    }
}
