import AppKit
import WebKit
import CerebralCore
import CerebralRuntimeHost
import os

/// Hosts the bundled production dashboard in a `WKWebView`, loaded offline over the
/// `cerebral://app/` origin (ADR-001, NIC-73 / FR-SHL-03).
///
/// The web view is opaque here so the native host matches the verified browser UI
/// exactly (FR-SHL-03 AC): the dashboard paints its own opaque background. Native
/// vibrancy/transparency (compositing web content over `NSVisualEffectView`) and the
/// WKWebView-vs-browser color-management deltas are tuned deliberately on real
/// hardware in NIC-77, not as unverified groundwork here. The React app is unchanged
/// and still runs against its in-webview mock bridge until NIC-74 wires the native
/// transport. Navigation failures are logged so a broken bundle is visible.
final class DashboardWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let controlHandlerName = "shellControl"

    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "dashboard")

    /// Web → native shell actions from the dashboard (NIC-76), e.g. rebinding the palette
    /// hotkey from the settings "Hotkeys" panel. Kept off the versioned/portable bridge —
    /// these are Mac-only window/shell concerns. Set by `WindowCoordinator`.
    var onShellControl: (([String: Any]) -> Void)?

    /// The root of the bundled dashboard build inside the app (`Resources/DashboardBundle`).
    static func bundledDashboardRoot() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("DashboardBundle", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: index.path) ? root : nil
    }

    init(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        // Register the native bridge transport before the web view is built. The
        // dashboard still runs its in-webview mock bridge until NIC-74c selects the
        // native transport; this makes the handshake channel available (ADR-004).
        bridge.install(on: configuration)

        // Inject the bootstrap state synchronously (before the app loads) so the
        // dashboard seeds its store with no round-trip or loading flash; the live
        // bridge then serves operations and the event stream (NIC-74c). Composed
        // by the session so the last active mode restores here too (FR-MOD-05).
        if let data = try? BridgeMessageCoding.encoder().encode(
            session.composeBootstrapState()
        ), let json = String(data: data, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "window.__cerebralBootstrap = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // Seed the settings "Hotkeys" panel with the current palette shortcut (NIC-76).
        let preset = PaletteShortcutPreset.current
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__cerebralHotkey = { preset: \"\(preset.rawValue)\", label: \"\(preset.label)\" };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        webView = WKWebView(frame: .zero, configuration: configuration)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm"
        window.center()
        window.contentView = webView

        super.init()
        bridge.attach(to: webView)
        bridge.bind(session: session)
        configuration.userContentController.add(self, name: Self.controlHandlerName)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: CerebralSchemeHandler.indexURL))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    /// Routes a shared-session bridge event (lifecycle/confirmation/config) to the
    /// dashboard webview. The app wires this as `AppBridgeRuntime`'s event sink.
    func deliverBridgeEvent(_ json: String) {
        bridge.deliverBridgeEvent(json)
    }

    /// Opens the Heimlich conversation in the center panel with `text` (NIC-76 / the
    /// palette's "Ask Heimlich" routing). Calls the dashboard's injected shell-intent hook;
    /// it is a no-op if the dashboard React tree has not mounted yet.
    func openConversation(_ text: String) {
        guard let literal = try? JSONEncoder().encode(text),
              let literalString = String(data: literal, encoding: .utf8) else { return }
        let script = "window.__cerebralShell && window.__cerebralShell.openConversation(\(literalString));"
        webView.evaluateJavaScript(script)
    }

    /// Opens the web settings overlay over the dashboard (NIC-76 / FR-UI-06). The native
    /// settings window is retired; the menu-bar "Settings…" routes here.
    func openSettings() {
        webView.evaluateJavaScript(
            "window.__cerebralShell && window.__cerebralShell.openSettings && window.__cerebralShell.openSettings();"
        )
    }

    // MARK: - WKScriptMessageHandler (web → native shell control)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.controlHandlerName, let body = message.body as? [String: Any] else { return }
        onShellControl?(body)
    }

    // MARK: - WKNavigationDelegate (surface load failures)

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard navigation failed: \(error.localizedDescription, privacy: .public)")
    }
}
