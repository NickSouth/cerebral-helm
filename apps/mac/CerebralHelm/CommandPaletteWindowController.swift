import AppKit
import WebKit
import CerebralCore
import CerebralRuntimeHost
import os

/// A panel that can become key so its hosted web input accepts typing even though the
/// app was in the background when the global hotkey fired.
private final class CommandPalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The floating command palette summoned by the global hotkey / menu bar (NIC-75 /
/// FR-SHL-02).
///
/// It is a single, reused `NSPanel` hosting a lightweight `WKWebView` route of the
/// dashboard (`index.html?surface=palette`) that renders only the existing
/// `CommandSurface` — token/visual parity with the dashboard, no forked input (owner
/// decision, see the command-palette memory). Its bridge transport binds the **shared**
/// `BridgeSession`, so a submitted command runs through the same runtime as the
/// dashboard. The panel + webview are built once at launch and kept warm, so `summon`
/// is only an activate + order-front (meeting the ~200ms latency target). Being a single
/// controller with a single panel, repeated invocation focuses the one palette rather
/// than creating duplicates (FR-SHL-02 AC).
///
/// A private `paletteControl` script-message channel lets the web layer ask the native
/// side to dismiss (on submit or Escape); it is intentionally separate from the
/// versioned bridge — window control is a native-app concern, not part of the contract.
final class CommandPaletteWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    static let controlHandlerName = "paletteControl"
    // Width matches the dashboard's top Ask-Heimlich bar (NIC-77): the palette is just that bar
    // floating over the dashboard, so the two read as the same control. The window is sized to the
    // content — bar height when empty, growing as the suggestion list appears (see `setPanelHeight`,
    // driven by the web layer's `resize` message) — so there is no box, just a bar.
    private static let width: CGFloat = 640
    /// A sanity floor only — the real height always comes from the web content's `resize`
    /// report, so the window hugs the bar exactly (no slack rectangle below it).
    private static let minHeight: CGFloat = 40
    private static let initialHeight: CGFloat = 56
    // Fixed screen-Y of the bar's TOP edge (upper third); the window grows downward from here.
    private var topEdgeY: CGFloat = 0

    private let panel: CommandPalettePanel
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "palette")

    /// Invoked when the palette submits a command. The coordinator brings the dashboard forward
    /// and dispatches the command through the shared bridge (the Heimlich chat was removed —
    /// NIC-124). The callback keeps its `onAskHeimlich` name to avoid churn across call sites.
    var onAskHeimlich: ((String) -> Void)?

    /// The screen the palette should appear on (NIC-120b: palette focus targets
    /// the main display). Set by the coordinator; nil falls back to the screen
    /// with keyboard focus.
    var targetScreen: (() -> NSScreen?)?

    private static var paletteURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=palette")!
    }

    init(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Increment 3: seed the palette with the active mode (and rest of the bootstrap) so
        // its first paint matches the dashboard's theme; `config.changed` events keep it in
        // sync thereafter. Composed by the session so the restored mode applies (FR-MOD-05).
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
        // The webview paints the bar colour edge-to-edge; clip its layer to rounded corners so the
        // window reads as a clean rounded bar (no square rim) regardless of webview transparency
        // support. `drawsBackground = false` is still attempted so it can be translucent where it
        // works, but the layout no longer depends on it (NIC-77).
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 14
        webView.layer?.masksToBounds = true

        panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        // The control channel is added after super.init so `self` can be the handler.
        configuration.userContentController.add(self, name: Self.controlHandlerName)

        // Transparent panel so the only thing drawn is the web pill — no window chrome, no box.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A soft shadow follows the opaque pill (or the bar-shaped window), so it floats like Spotlight.
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = webView
        panel.delegate = self

        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self

        // Pre-warm: load now and keep the panel off-screen/hidden, so the first summon is
        // instant (the React palette is already mounted).
        webView.load(URLRequest(url: Self.paletteURL))
    }

    /// Show (or refocus) the single palette, centered in the upper third of the active
    /// screen, and focus the input. Idempotent: never creates a second panel.
    func summon() {
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Focus (and select) the input each summon so typing starts immediately even when
        // the pre-warmed webview was previously hidden.
        webView.evaluateJavaScript("window.__cerebralFocusPalette && window.__cerebralFocusPalette();")
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    /// Increment 3: forward a `config.changed` event to the palette webview so it re-themes
    /// to the active mode. The coordinator only routes mode events here.
    func deliverBridgeEvent(_ json: String) {
        bridge.deliverBridgeEvent(json)
    }

    private func position() {
        guard let screen = targetScreen?() ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - Self.width / 2
        let height = panel.frame.height // keep whatever the content sized the bar to
        // Anchor the TOP edge in the upper third (Spotlight-like); the window grows downward.
        topEdgeY = visible.midY + visible.height * 0.30
        panel.setFrame(NSRect(x: x, y: topEdgeY - height, width: Self.width, height: height), display: false)
    }

    /// Size the window to the web content's height (bar-only, or taller with the suggestion list),
    /// keeping the bar's top edge fixed so it grows downward like Spotlight.
    private func setPanelHeight(_ raw: CGFloat) {
        let anchor = topEdgeY > 0 ? topEdgeY : panel.frame.origin.y + panel.frame.height
        let maxHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = max(Self.minHeight, min(raw, maxHeight - 80))
        panel.setFrame(
            NSRect(x: panel.frame.origin.x, y: anchor - height, width: Self.width, height: height),
            display: true
        )
        // A clear, layer-clipped window keeps a stale shadow shape after resizing; recompute it.
        panel.invalidateShadow()
    }

    // MARK: - paletteControl channel (web → native window control)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "dismiss":
            // Escape / click-away dismiss the palette.
            dismiss()
        case "resize":
            // The web layer reports its content height so the window is just the bar (growing for
            // the suggestion list) rather than a fixed box (NIC-77).
            if let height = body["height"] as? NSNumber {
                setPanelHeight(CGFloat(truncating: height))
            }
        case "askHeimlich":
            // A palette submission dismisses the palette and routes to the dashboard's command
            // bus via the coordinator (the Heimlich chat was removed — NIC-124). The control
            // action keeps its `askHeimlich` name to avoid churn across the native boundary.
            dismiss()
            onAskHeimlich?((body["text"] as? String) ?? "")
        default:
            log.error("Unknown paletteControl action: \(action, privacy: .public)")
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Click-away / focus loss dismisses the palette (Spotlight behavior).
        dismiss()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Palette failed to load: \(error.localizedDescription, privacy: .public)")
    }

    /// WebKit reclaims the content process of long-hidden windows — exactly the
    /// pre-warmed palette's life. Without a reload the next summon shows the dead
    /// renderer (a solid green/blank panel, no input). Reload so a summon after
    /// hours idle still gets a live palette.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Palette web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.paletteURL))
    }
}
