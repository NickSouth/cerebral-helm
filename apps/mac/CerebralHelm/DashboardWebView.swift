import AppKit
import WebKit
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
final class DashboardWindowController: NSObject, WKNavigationDelegate {
    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "dashboard")

    /// The root of the bundled dashboard build inside the app (`Resources/DashboardBundle`).
    static func bundledDashboardRoot() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("DashboardBundle", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: index.path) ? root : nil
    }

    init(dashboardRoot: URL) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        // Register the native bridge transport before the web view is built. The
        // dashboard still runs its in-webview mock bridge until NIC-74c selects the
        // native transport; this makes the handshake channel available (ADR-004).
        bridge.install(on: configuration)

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
        webView.navigationDelegate = self
        webView.load(URLRequest(url: CerebralSchemeHandler.indexURL))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - WKNavigationDelegate (surface load failures)

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard navigation failed: \(error.localizedDescription, privacy: .public)")
    }
}
