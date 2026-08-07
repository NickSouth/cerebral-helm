import AppKit
import WebKit
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import os

/// The More Apps launcher window (NIC-148).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so
/// the launcher — which must sit in front of whatever the user is looking at —
/// is its own **floating**, top-most window rather than an in-backdrop overlay
/// that could be covered (the same backdrop-policy reasoning as the settings
/// window). It hosts `index.html?surface=moreapps` over the **shared**
/// `BridgeSession` (the palette/settings pattern: one runtime, multiple
/// transports), so it reads capabilities and app discovery identically to the
/// dashboard and launches through the same command bus.
///
/// Frameless like the settings window: the web surface draws its own themed × and
/// title, so the macOS title bar and traffic lights are hidden. Unlike settings it
/// is **not** reused warm — the coordinator builds a fresh controller on each open
/// so the app list and capabilities are current, and tears it down on close (it is
/// a transient launcher that dismisses the moment an app is opened, NIC-148).
final class MoreAppsWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "moreapps")

    /// Web → native shell actions (closeMoreApps). Set by `WindowCoordinator`,
    /// which owns the action routing.
    var onShellControl: (([String: Any]) -> Void)?

    /// The centre of the control that summoned this window, in screen coordinates. Recorded by
    /// whichever `position*` call placed the window, so the launcher recedes back into the button
    /// it flew out of rather than fading on the spot.
    private var anchorPoint: NSPoint?

    private static var moreAppsURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=moreapps")!
    }

    init(dashboardRoot: URL, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme + modes + capabilities on first
        // paint, no loading flash) — composed by the session so the launcher gates
        // on the same live capabilities as the dashboard.
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

        // A tall, narrow launcher (owner decision): three fixed columns of apps, scroll for
        // more. Sized to the web surface's design dimensions.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "All applications"
        // Frameless chrome: the web surface draws its own × (shellControl
        // `closeMoreApps`) and title, so the macOS title bar and traffic lights are
        // redundant. Hide them and let the content fill edge-to-edge.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Top-most so it sits in front of whatever the user is looking at — the
        // backdrop never lifts, so the launcher must float above other apps.
        window.level = .floating
        // Follows the user across Spaces and appears over full-screen apps — a
        // launcher summoned anywhere must be reachable without a Space switch.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        // Translucent over the desktop (2026-08-06 direction): the launcher is a big transparent
        // sheet of icons, so the tiles are the only thing that reads as solid.
        VibrantWindowChrome.apply(to: window, hosting: webView)

        super.init()
        window.delegate = self
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Self.moreAppsURL))
    }

    /// Drop the launcher directly under the More Apps button (owner preference,
    /// NIC-148): horizontally centered on the button and just below its bottom edge,
    /// clamped to the screen's visible frame so it never runs off an edge. `anchor`
    /// is the button's rect in screen coordinates (AppKit, y-up).
    func positionUnder(_ anchor: NSRect, on screen: NSScreen) {
        let gap: CGFloat = 8
        let visible = screen.visibleFrame
        var frame = window.frame
        let originX = min(
            max(anchor.midX - frame.width / 2, visible.minX + 8),
            visible.maxX - frame.width - 8
        )
        let originY = max(anchor.minY - gap - frame.height, visible.minY + 8)
        frame.origin = NSPoint(x: originX, y: originY)
        window.setFrame(frame, display: true)
        anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
    }

    /// Fallback placement when the button's anchor isn't known: toward the right
    /// edge of the screen, vertically centered, clear of the edge.
    func positionOnRight(of screen: NSScreen) {
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        var frame = window.frame
        frame.origin.x = visible.maxX - frame.width - margin
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrame(frame, display: true)
        // Pinned to the right edge with no button behind it, so the edge itself is where it comes
        // from — a launcher sliding in off the side of the screen it is parked against.
        anchorPoint = NSPoint(x: visible.maxX, y: frame.midY)
    }

    func show() {
        WindowAppearance.present(window, emergingFrom: anchorPoint)
    }

    func close() {
        WindowAppearance.dismiss(window, receding: anchorPoint) { [window] in
            window.orderOut(nil)
        }
    }

    /// Tear down without the dismissal animation, for when this window is being *replaced* by a
    /// freshly-built one in the same place. Fading the outgoing copy out while its identical
    /// replacement fades in over it reads as a flicker rather than as a transition — a replacement
    /// is not a dismissal and should not be animated like one.
    func closeImmediately() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the launcher re-gates and re-themes
    /// live while it's open (a capability flip mid-session, a mode switch).
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
        log.error("More Apps surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    /// WebKit killed the content process (memory pressure). Reload so the window
    /// never shows the dead-renderer artifact.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("More Apps web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.moreAppsURL))
    }
}
