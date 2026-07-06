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
/// The backdrop window (NIC-120a): borderless windows refuse key status by
/// default, but the hosted web input (command bar, conversation, settings)
/// must accept typing whenever the dashboard is focused.
private final class DashboardBackdropWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DashboardWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let controlHandlerName = "shellControl"

    /// One level below normal windows (NIC-120a backdrop): above the desktop
    /// and its icons, below every normal app window — opened apps naturally
    /// layer over the dashboard without a Space switch. Deliberately not a
    /// Stage Manager / fullscreen API (PRD §3.2 non-goal).
    ///
    /// This level is **permanent** (backdrop-policy decision, 2026-07-06): the
    /// dashboard never rises above normal windows — clicking it must not raise
    /// it, and minimizing/hiding apps is how it gets revealed. Anything that
    /// must be seen above other apps gets its own window (palette pattern),
    /// never a dashboard lift.
    static let backdropLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

    let window: NSWindow
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "dashboard")

    /// Web → native shell actions from the dashboard (NIC-76), e.g. rebinding the palette
    /// hotkey from the settings "Hotkeys" panel. Kept off the versioned/portable bridge —
    /// these are Mac-only window/shell concerns. Set by `WindowCoordinator`.
    var onShellControl: (([String: Any]) -> Void)?

    /// Fired when the dashboard page finishes loading. The coordinator replays
    /// runtime-only state that predates the page (the cached display topology) —
    /// an event emitted before `__cerebralReceive` exists is otherwise lost.
    var onLoaded: (() -> Void)?

    /// The root of the bundled dashboard build inside the app (`Resources/DashboardBundle`).
    static func bundledDashboardRoot() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("DashboardBundle", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: index.path) ? root : nil
    }

    /// `screen`: the display this backdrop covers. The main backdrop passes nil
    /// (primary); secondary backdrops (NIC-120b, one per connected display) pass
    /// their display's screen. All backdrops share the one `BridgeSession`.
    init(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession, screen: NSScreen? = nil) {
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

        // The desktop backdrop (NIC-120a): borderless and sized to the primary
        // screen, on all Spaces, stationary through Mission Control transitions.
        // Fullscreen usage is retired — the dashboard is the persistent surface
        // *behind* normal windows, so opening an app layers it above CerebralHelm
        // instead of switching Spaces. Multi-display backdrops follow in NIC-120b;
        // until then a secondary display shows the plain desktop.
        let screenFrame = (screen ?? NSScreen.screens.first ?? NSScreen.main)?.frame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = DashboardBackdropWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm"
        window.level = Self.backdropLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
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

    /// Show without taking key focus — secondary backdrops (NIC-120b) must never
    /// steal typing from whatever the user is doing on the main display.
    func showWithoutFocus() {
        window.orderFront(nil)
    }

    /// Fit the backdrop to the given screen — the coordinator calls this on every
    /// topology change (NIC-87/120b), so a disconnect, re-arrangement, or
    /// main-display re-target never leaves a backdrop mis-sized or stranded.
    func fit(to screen: NSScreen) {
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoaded?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard failed to load: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("Dashboard navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    /// WebKit reclaims the content process of fully-occluded windows — a covered
    /// backdrop qualifies. Reload so revealing the dashboard never shows a dead
    /// renderer.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Dashboard web content process terminated; reloading.")
        webView.load(URLRequest(url: CerebralSchemeHandler.indexURL))
    }
}
