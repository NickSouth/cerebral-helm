import AppKit
import WebKit
import CerebralCore
import CerebralRuntimeHost
import os

/// A borderless panel that can become key so Escape and click-away dismissal work even
/// though the app may have been in the background when the trigger was clicked.
private final class ModeMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The mode-swap dropdown window (NIC-144).
///
/// The dashboard is a strict backdrop that never rises above normal windows, so the
/// mode menu — which must be usable while apps are open — is its own transparent,
/// top-most window rather than the in-backdrop `<ul>` (which would be covered). It hosts
/// `index.html?surface=modemenu` over the **shared** `BridgeSession` (the palette / More
/// Apps pattern: one runtime, multiple transports), so a mode switch runs through the
/// same command bus as the dashboard.
///
/// Transparent like the palette (`drawsBackground = false`, clear window) so only the
/// menu paints and the web layer can grow it up + fade it in. Built fresh on each open
/// and torn down on close — a transient menu, not a warm-reused panel. Every dismissal
/// path (a selection, Escape, or clicking away) routes through `closeModeMenu` so the
/// coordinator owns the window's lifecycle.
final class ModeMenuWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "modemenu")

    /// Web → native shell actions (closeModeMenu). Set by `WindowCoordinator`, which
    /// owns the action routing and the window's lifecycle.
    var onShellControl: (([String: Any]) -> Void)?

    private static var modeMenuURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=modemenu")!
    }

    init(dashboardRoot: URL, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously (theme + modes + active mode on first paint,
        // no loading flash) — composed by the session so the menu highlights the same
        // active mode as the dashboard.
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
        // Transparent web content so only the menu (which draws its own themed surface and
        // shadow) paints — the window shows the desktop everywhere else. Standard technique,
        // already used by the command palette.
        webView.setValue(false, forKey: "drawsBackground")

        // A small window sized to the four-mode menu; the web surface pins the menu to the
        // bottom and grows it upward, so any slack above the menu is transparent.
        window = ModeMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // The menu draws its own CSS shadow; a window shadow would frame the whole
        // (transparent) rect instead.
        window.hasShadow = false
        // Top-most so it sits above whatever the user is looking at — the backdrop never
        // lifts, so the dropdown must float above other apps and across Spaces.
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
        webView.load(URLRequest(url: Self.modeMenuURL))
    }

    /// Drop the dropdown directly above the mode trigger: horizontally centered on it and
    /// just above its top edge, clamped to the screen's visible frame. `anchor` is the
    /// trigger's rect in screen coordinates (AppKit, y-up).
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

    /// Fallback placement when the trigger's anchor isn't known: bottom-center, where the
    /// bar's mode control lives.
    func positionBottomCenter(on screen: NSScreen) {
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 72)
        window.setFrame(frame, display: true)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    /// Route a shared-session bridge event so the menu re-themes / re-highlights live if
    /// the mode changes from elsewhere while it's open.
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
        // Click-away / focus loss dismisses the dropdown (menu behavior) — routed through
        // the coordinator so there is one close path that also clears its reference.
        onShellControl?(["action": "closeModeMenu"])
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Mode menu surface failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Mode menu web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.modeMenuURL))
    }
}
