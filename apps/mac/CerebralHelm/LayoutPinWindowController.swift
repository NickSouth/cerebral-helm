import AppKit
import WebKit
import CerebralCore
import CerebralRuntimeHost
import os

/// A borderless panel that can become key so Escape and click-away dismissal work
/// even though the app may have been in the background when the "+" was clicked.
private final class LayoutPinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The layout hotswap "+" window (NIC-142).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so the
/// pin picker — which must sit above the open layout windows — is its own transparent,
/// top-most window rather than an in-backdrop overlay (which would be covered). It hosts
/// `index.html?surface=layoutpin` over the **shared** `BridgeSession` (the palette /
/// More Apps / mode-menu pattern: one runtime, multiple transports), so it reads app
/// discovery and mints references through the same command bus as the dashboard, and its
/// session-only adds (`addLayoutTarget`) land on the same live layout session.
///
/// Transparent and borderless like the mode-swap dropdown (`drawsBackground = false`,
/// clear window) so only the floating pin card paints and it overlaps the open windows.
/// Built fresh on each open and torn down on close — a transient picker, not a warm
/// panel. Unlike More Apps it stays open across adds (pin several hotswaps); every
/// dismissal path (the ×, Escape, or clicking away) routes through `closeLayoutPin` so
/// the coordinator owns the window's lifecycle.
final class LayoutPinWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "layoutpin")

    /// Web → native shell actions (closeLayoutPin). Set by `WindowCoordinator`, which
    /// owns the action routing and the window's lifecycle.
    var onShellControl: (([String: Any]) -> Void)?

    private static var layoutPinURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=layoutpin")!
    }

    init(dashboardRoot: URL, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme + modes + capabilities on first paint,
        // no loading flash) — composed by the session so the picker gates on the same
        // live capabilities and app discovery as the dashboard.
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
        // Transparent web content so only the pin card (which draws its own themed
        // surface + shadow) paints — the window shows the desktop everywhere else. The
        // same technique the command palette and mode-menu use.
        webView.setValue(false, forKey: "drawsBackground")

        // Sized to the pin card (like the Quick Apps pin popover); the card fills the
        // window and internally scrolls its app list.
        window = LayoutPinPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // The card draws its own CSS shadow; a window shadow would frame the whole
        // (transparent) rect instead.
        window.hasShadow = false
        // Top-most so it sits above the open layout windows — the backdrop never lifts,
        // so the picker must float above other apps and across Spaces.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = webView

        super.init()
        window.delegate = self
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Self.layoutPinURL))
    }

    /// Drop the picker directly above the "+": horizontally centered on it and just
    /// above its top edge, clamped to the screen's visible frame. `anchor` is the
    /// button's rect in screen coordinates (AppKit, y-up).
    func positionAbove(_ anchor: NSRect, on screen: NSScreen) {
        let gap: CGFloat = 8
        let visible = screen.visibleFrame
        var frame = window.frame
        let originX = min(
            max(anchor.midX - frame.width / 2, visible.minX + 8),
            visible.maxX - frame.width - 8
        )
        let originY = min(anchor.maxY + gap, visible.maxY - frame.height)
        frame.origin = NSPoint(x: originX, y: max(originY, visible.minY + 8))
        window.setFrame(frame, display: true)
    }

    /// Fallback placement when the "+" anchor isn't known: bottom-left, where the
    /// layout pill's "+" lives.
    func positionBottomLeft(on screen: NSScreen) {
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin = NSPoint(x: visible.minX + 24, y: visible.minY + 72)
        window.setFrame(frame, display: true)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the picker re-gates / re-themes live if a
    /// capability flips or the mode changes while it's open.
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

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Click-away / focus loss dismisses the picker (menu behavior) — routed through
        // the coordinator so there is one close path that also clears its reference.
        onShellControl?(["action": "closeLayoutPin"])
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Layout pin surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Layout pin web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.layoutPinURL))
    }
}
