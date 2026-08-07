import AppKit
import WebKit
import CerebralCore
import CerebralRuntimeHost
import os

/// A panel that takes keyboard focus without activating CerebralHelm.
///
/// `canBecomeKey` is what lets the hosted command input accept typing. Paired with
/// `.nonactivatingPanel` in the style mask it does so **without** making CerebralHelm the
/// active app — which is the whole trick behind drawing over another app's fullscreen Space.
private final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The left-edge sidebar: the dashboard's controls in one narrow column, reachable from inside a
/// fullscreen app or on a single monitor.
///
/// **Why it is a panel and not part of the backdrop.** The dashboard never rises above normal
/// windows (backdrop-policy decision, 2026-07-06). Anything that must be seen over other apps gets
/// its own window — the palette pattern — so this is a floating panel hosting
/// `index.html?surface=sidebar` on the **shared** `BridgeSession`. One runtime, another transport:
/// a mode switched here is the mode everywhere, and a command run here goes through the same bus
/// with the same confirmation policy.
///
/// **The fullscreen-overlay configuration is load-bearing and was verified on-device** (2026-08-03),
/// after the palette failed this exact test with a partial version of it:
///   - `.nonactivatingPanel` in the style mask — take key focus without activating the app.
///   - `.fullScreenAuxiliary` — permitted to draw over a fullscreen app.
///   - `.canJoinAllSpaces` — follows the user across every Space.
///   - `.transient` + `.ignoresCycle` — stays out of Exposé and ⌘` cycling.
///   - **No `NSApp.activate(ignoringOtherApps:)` on summon.** CerebralHelm is a `.regular` app
///     (main.swift), and activating a regular app makes macOS leave the frontmost app's fullscreen
///     Space — the panel then opens on the desktop Space, invisible from where the user actually is.
///     This single call was the original failure; do not reintroduce it.
///
/// Two private script-message channels, both deliberately off the versioned bridge because window
/// control is a native-app concern: `sidebarControl` (dismiss / pin / unpin) and the shared
/// `shellControl` (quick-app pinning, More Apps, settings) routed to the coordinator.
final class SidebarWindowController: NSObject, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    static let controlHandlerName = "sidebarControl"

    /// The private channel carrying this surface's glass geometry. Separate from the control
    /// channels because it is window presentation, not an action: it fires many times a second
    /// while the column scrolls.
    static let glassHandlerName = "glassControl"

    /// Wide enough for the two-up quick-action grid and the Today panel to read, narrow enough to
    /// leave the underlying app usable. The web column scales its type off viewport *height*, so
    /// this stays a fixed point width rather than a proportion of the screen.
    private static let width: CGFloat = 340

    /// Long enough to read as a deliberate slide, short enough that the sidebar never feels like
    /// something you wait for (roughly the Dock's own reveal).
    private static let slideDuration: TimeInterval = 0.22

    /// True while the tuck-away animation is running. The panel is still `isVisible` then, so
    /// every entry point checks this to avoid re-entrancy: a summon mid-tuck must cancel it
    /// rather than race it, and the completion handler must not order out a panel that has since
    /// been summoned again.
    private var isHiding = false

    private let panel: SidebarPanel
    private let webView: WKWebView
    private let handler: CerebralSchemeHandler
    private let bridge = WKWebViewCerebralBridge()
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "sidebar")

    /// Web → native shell actions (quick-app pinning, More Apps, settings), routed by the
    /// coordinator exactly as the dashboard's are. Set by `WindowCoordinator`.
    var onShellControl: (([String: Any]) -> Void)?

    /// The screen the sidebar belongs to. Set by the coordinator; nil falls back to the screen
    /// with keyboard focus.
    var targetScreen: (() -> NSScreen?)?

    /// A Report/Input quick action asked to open on the dashboard rather than in the column.
    /// Exactly one of the two ids is non-nil. Routed by the coordinator, which owns the dashboard.
    var onRevealDashboard: ((String?, String?) -> Void)?

    /// While pinned the sidebar stays put when focus moves elsewhere, instead of tucking away.
    /// Driven from the web layer's pin control over `sidebarControl`.
    private(set) var pinned = false

    /// Renders one desktop blur per pane the web layer reports (`glassControl`).
    private var glassHost: GlassBlurHost?

    private static var sidebarURL: URL {
        URL(string: "\(CerebralSchemeHandler.scheme)://\(CerebralSchemeHandler.host)/index.html?surface=sidebar")!
    }

    init(dashboardRoot: URL, paths: WorkspacePaths, session: BridgeSession) {
        handler = CerebralSchemeHandler(root: dashboardRoot)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: CerebralSchemeHandler.scheme)
        bridge.install(on: configuration)

        // Seed the bootstrap synchronously so the first paint already carries the active mode's
        // theme and regions — no loading flash on the first summon (the dashboard/palette pattern).
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

        panel = SidebarPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600),
            // Borderless: a full-height edge panel has no use for a title bar, and the web surface
            // owns its own header. Matches the existing dropdown panels (ModeMenu / LayoutPin).
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configuration.userContentController.add(self, name: Self.controlHandlerName)
        configuration.userContentController.add(self, name: DashboardWindowController.controlHandlerName)
        configuration.userContentController.add(self, name: Self.glassHandlerName)

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // No material behind it (owner, 2026-08-07): the column is a set of floating panes, and
        // everything that is not a pane is completely transparent. A window-level
        // `NSVisualEffectView` blurs the whole rect — on a full-height column that is an enormous
        // slab of blur for a handful of controls, which is exactly how it looked. The panes carry
        // their own legibility in CSS, where their geometry already lives.
        glassHost = VibrantWindowChrome.clear(window: panel, hosting: webView)
        panel.delegate = self

        bridge.attach(to: webView)
        bridge.bind(session: session)
        webView.navigationDelegate = self

        // Pre-warm: load now and keep the panel off screen, so the first reveal is instant.
        webView.load(URLRequest(url: Self.sidebarURL))
    }

    /// Show (or refocus) the single sidebar and focus its command input. Idempotent — never
    /// creates a second panel.
    ///
    /// The column slides out from behind the screen edge (Dock-like) rather than appearing in
    /// place: the panel is ordered in already off-screen, then animated to its resting frame, so
    /// the motion reads as the sidebar emerging from the edge it lives on.
    /// How the sidebar was brought out. The two entry points behave differently in two ways:
    ///
    /// - **Focus.** The hotkey opens the column ready to type; a hover reveal leaves the command
    ///   box alone, because an autofocused input dropping a suggestion list over the column reads
    ///   as noise when the user only moved their pointer (owner feedback, 2026-08-03).
    /// - **Auto-collapse.** A hover reveal tucks itself away when the pointer leaves, the way any
    ///   flyout does. A hotkey summon must NOT: the pointer is wherever the user left it — very
    ///   often already outside the column — so it would close the instant it opened.
    enum RevealSource {
        case hotkey
        case edge
    }

    private(set) var revealSource: RevealSource = .hotkey

    /// The rect a hover-revealed sidebar must keep the pointer inside to stay open, or nil when
    /// nothing should auto-collapse — hidden, pinned, or summoned by the hotkey.
    var hoverFrame: NSRect? {
        guard isVisible, revealSource == .edge, !pinned else { return nil }
        return panel.frame
    }

    func summon(from source: RevealSource = .hotkey) {
        revealSource = source
        let focusingCommand = source == .hotkey
        // Already out (or on its way out): settle focus, never restart the slide.
        guard !panel.isVisible || isHiding else {
            applyCommandFocus(focusingCommand)
            return
        }
        isHiding = false
        let resting = restingFrame()
        guard !Self.motionStilled else {
            panel.setFrame(resting, display: false)
            panel.makeKeyAndOrderFront(nil)
            applyCommandFocus(focusingCommand)
            return
        }
        // Start fully off the left edge, ordered in but invisible to the user, then run in.
        panel.setFrame(Self.hidden(from: resting), display: false)
        // No NSApp.activate — see the type comment. This is what keeps a fullscreen app's Space.
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(resting, display: true)
        }
        // Settle focus immediately rather than on completion: the input must accept the user's
        // first keystroke even if they start typing before the slide finishes.
        applyCommandFocus(focusingCommand)
    }

    /// Focus (and select) the command input, so a hotkey summon starts typing immediately. Blur
    /// first: after a dismiss the input is often still `document.activeElement`, making a bare
    /// `.focus()` a no-op that fires no event and leaves React's focus state stale (the fix the
    /// palette needed for the same reason).
    func focusCommand() {
        webView.evaluateJavaScript("window.__cerebralFocusSidebar && window.__cerebralFocusSidebar();")
    }

    /// Explicitly clear focus from the command input. Needed on a hover reveal because the
    /// pre-warmed webview keeps whatever focus it had when it was last dismissed — without this
    /// the box would still be active (and its suggestion list open) from the previous summon.
    func blurCommand() {
        webView.evaluateJavaScript("window.__cerebralBlurSidebar && window.__cerebralBlurSidebar();")
    }

    private func applyCommandFocus(_ shouldFocus: Bool) {
        if shouldFocus {
            focusCommand()
        } else {
            blurCommand()
        }
    }

    /// Tuck the column back behind the left edge, then order it out once it is out of sight.
    func dismiss() {
        guard panel.isVisible, !isHiding else { return }
        guard !Self.motionStilled else {
            panel.orderOut(nil)
            return
        }
        isHiding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(Self.hidden(from: panel.frame), display: true)
        } completionHandler: { [weak self] in
            guard let self, self.isHiding else { return }
            self.isHiding = false
            self.panel.orderOut(nil)
        }
    }

    var isVisible: Bool { panel.isVisible && !isHiding }

    /// Hotkey behavior: summon when hidden, tuck away when already showing. A panel mid-tuck
    /// counts as hidden, so a fast double-press re-opens rather than doing nothing.
    func toggle() {
        if isVisible {
            dismiss()
        } else {
            summon()
        }
    }

    /// Route a shared-session bridge event into the sidebar webview. The column renders the live
    /// widgets (schedule, quick apps, agents), so it takes the full event stream like the
    /// dashboard — not the palette's mode-only subset.
    func deliverBridgeEvent(_ json: String) {
        bridge.deliverBridgeEvent(json)
    }

    /// The column's resting place: flush against the left edge of the target screen, spanning its
    /// full usable height. `visibleFrame` (not `frame`) so it starts below the menu bar on the
    /// desktop Space and clears the Dock if the Dock is on the left.
    private func restingFrame() -> NSRect {
        guard let screen = targetScreen?() ?? NSScreen.main else { return panel.frame }
        let visible = screen.visibleFrame
        return NSRect(x: visible.minX, y: visible.minY, width: Self.width, height: visible.height)
    }

    /// The same frame pushed fully off the left edge — the slide's start point and end point.
    /// One pixel of overlap past the width avoids a hairline of the panel's shadow staying visible.
    private static func hidden(from resting: NSRect) -> NSRect {
        NSRect(x: resting.minX - resting.width - 1, y: resting.minY, width: resting.width, height: resting.height)
    }

    /// Honor the system "Reduce motion" setting: the sidebar still appears, it just does not
    /// travel. (The app-level reduced-motion override lives in the web settings store and is not
    /// readable from here yet — folding that in belongs with the settings-read work.)
    private static var motionStilled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - sidebarControl channel (web → native window control)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        // Glass geometry is pure presentation of this window, and arrives many times a second while
        // the column scrolls — it never reaches the action routing below.
        if message.name == Self.glassHandlerName {
            let raw = body["rects"] as? [[String: Any]] ?? []
            glassHost?.update(rects: raw.compactMap(GlassRect.init))
            return
        }
        // Shell actions (quick-app pinning, More Apps, settings) belong to the coordinator, which
        // already owns that routing for the dashboard.
        if message.name == DashboardWindowController.controlHandlerName {
            onShellControl?(body)
            return
        }
        guard let action = body["action"] as? String else { return }
        switch action {
        case "dismiss":
            dismiss()
        case "revealDashboard":
            // A Report/Input quick action: the column tucks away and the surface opens on the
            // dashboard instead. The web layer has already stowed the covering windows through
            // the collapse bucket, so by the time this lands the dashboard is what's visible.
            dismiss()
            onRevealDashboard?(body["report"] as? String, body["input"] as? String)
        case "pin":
            pinned = true
        case "unpin":
            pinned = false
        default:
            log.error("Unknown sidebarControl action: \(action, privacy: .public)")
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Click-away tucks the sidebar back to the edge, unless the user pinned it open.
        guard !pinned else { return }
        dismiss()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("Sidebar failed to load: \(error.localizedDescription, privacy: .public)")
    }

    /// WebKit reclaims the content process of long-hidden windows — exactly a pre-warmed sidebar's
    /// life. Without a reload the next summon shows a dead renderer.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("Sidebar web content process terminated; reloading.")
        webView.load(URLRequest(url: Self.sidebarURL))
    }
}
