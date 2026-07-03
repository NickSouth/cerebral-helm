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
    private static let width: CGFloat = 680
    private static let height: CGFloat = 420

    private let panel: CommandPalettePanel
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "palette")

    private static var paletteURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=palette")!
    }

    init(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        webView = WKWebView(frame: .zero, configuration: configuration)

        panel = CommandPalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        // The control channel is added after super.init so `self` can be the handler.
        configuration.userContentController.add(self, name: Self.controlHandlerName)

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

    private func position() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - Self.width / 2
        let y = visible.midY + visible.height * 0.10 // upper third, Spotlight-like
        panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: Self.height), display: false)
    }

    // MARK: - paletteControl channel (web → native window control)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "dismiss":
            // Submit + Escape both route here. Executing a command dismisses the palette;
            // bringing the dashboard forward for "Ask Heimlich" is NIC-76 window-role work.
            dismiss()
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
}
