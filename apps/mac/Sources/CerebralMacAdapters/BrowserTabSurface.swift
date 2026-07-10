// Browser tab surfacing (NIC-145). When CH re-triggers a URL it already opened
// in the current mode, the URL adapter asks this seam to focus the *existing*
// browser tab instead of opening a duplicate. macOS gives `NSWorkspace.open` no
// tab handle, so surfacing is done through AppleScript against the running
// default browser; the dialect differs per browser family.
//
// Matching is by **domain**, not exact route (NIC-145 follow-up): a pinned URL
// often redirects (adds a subdomain, a path, or flips scheme), so an exact-URL
// match would miss the redirected tab and open a duplicate. Instead the runner
// enumerates the browser's open tabs and Swift picks the first whose host matches
// the pinned host at a label boundary (so `example.com` matches `www.example.com`
// and `app.example.com`, but never `notexample.com`). Any tab on the domain is
// surfaced — the intended behavior for a pinned site that moves you around.
//
// Two layers, mirroring `AXWindowSurface`/`AXWindowCapability`:
//   * `BrowserScriptRunner` — the low-level native primitives (default-browser
//     resolution + AppleScript enumerate/focus). Its live implementation is
//     covered by manual smoke on hardware; contract tests never send Apple Events.
//   * `DefaultBrowserTabSurface` — the domain match and outcome mapping, which are
//     pure and unit-tested with a fake runner.
//
// Every non-`surfaced` outcome means "the caller should just open fresh" — a
// deliberately graceful degradation (unsupported browser, no match, or denied
// Automation permission never errors; NIC-145 owner decision: no permission gate
// on `url.open`). This target compiles empty on non-Apple platforms so the
// package graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation

/// The result of asking to surface a URL's tab in the default browser.
public enum BrowserSurfaceOutcome: Equatable, Sendable {
    /// An existing tab on the URL's domain was focused; do not open a new one.
    case surfaced
    /// The browser is scriptable but no open tab is on the domain; open fresh.
    case notFound
    /// The default browser exposes no scriptable tab control we support; open fresh.
    case unsupported(String)
    /// Automation (Apple Events) permission was denied; open fresh.
    case denied
}

/// The AppleScript dialect a browser understands for per-tab URL control.
public enum BrowserFamily: Equatable, Sendable {
    /// Safari's `current tab` scripting model.
    case safari
    /// The Chromium `active tab index` scripting model (Chrome, Brave, Edge,
    /// Vivaldi — same scripting dictionary).
    case chromium

    /// The dialect for a bundle id, or `nil` when the browser exposes no
    /// per-tab URL control we support (Arc, Firefox, …) — the caller opens fresh.
    public static func forBundleID(_ bundleID: String) -> BrowserFamily? {
        switch bundleID {
        case "com.apple.Safari",
             "com.apple.SafariTechnologyPreview":
            return .safari
        case "com.google.Chrome",
             "com.google.Chrome.beta",
             "com.google.Chrome.canary",
             "com.brave.Browser",
             "com.brave.Browser.beta",
             "com.brave.Browser.nightly",
             "com.microsoft.edgemac",
             "com.microsoft.edgemac.Beta",
             "com.microsoft.edgemac.Dev",
             "com.vivaldi.Vivaldi":
            return .chromium
        default:
            return nil
        }
    }
}

/// A single open browser tab, addressed by 1-based window and tab index within
/// the running browser at the moment it was enumerated.
public struct BrowserTabRef: Equatable, Sendable {
    public let windowIndex: Int
    public let tabIndex: Int
    public let url: String

    public init(windowIndex: Int, tabIndex: Int, url: String) {
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.url = url
    }
}

/// The outcome of enumerating a browser's open tabs.
public enum BrowserTabQuery: Equatable, Sendable {
    /// The tabs currently open (empty when the browser is not running — nothing
    /// to surface, so the caller opens fresh).
    case tabs([BrowserTabRef])
    /// Automation permission for the browser was denied.
    case denied
    /// The enumeration script failed unexpectedly (compile/runtime error).
    case failed(String)
}

/// Low-level seam over the AppleScript bridge, so the domain-match logic is
/// testable with a fake while the live implementation touches real Apple Events.
public protocol BrowserScriptRunner: Sendable {
    /// Bundle id of the default handler for `https`, or `nil` when none resolves.
    func defaultBrowserBundleID() -> String?
    /// The open tabs of the running browser with `bundleID`. Never launches it.
    func openTabs(bundleID: String, family: BrowserFamily) -> BrowserTabQuery
    /// Bring the given 1-based window/tab to the front. `false` when it could not
    /// (e.g. the window closed since it was enumerated) — the caller opens fresh.
    func focusTab(bundleID: String, family: BrowserFamily, windowIndex: Int, tabIndex: Int) -> Bool
}

/// Focus an existing browser tab for a URL's domain, or report why it could not.
public protocol BrowserTabSurface: Sendable {
    func surface(url: URL) async -> BrowserSurfaceOutcome
}

/// Resolves the default browser, enumerates its tabs, matches by domain, and
/// focuses the match. Pure aside from the injected runner.
public struct DefaultBrowserTabSurface: BrowserTabSurface {
    private let runner: any BrowserScriptRunner

    public init(runner: any BrowserScriptRunner = SystemBrowserScriptRunner()) {
        self.runner = runner
    }

    public func surface(url: URL) async -> BrowserSurfaceOutcome {
        guard let bundleID = runner.defaultBrowserBundleID() else {
            return .unsupported("No default browser is configured to surface this URL.")
        }
        guard let family = BrowserFamily.forBundleID(bundleID) else {
            return .unsupported("The default browser (\(bundleID)) exposes no scriptable tab control.")
        }
        guard let targetHost = url.host, !targetHost.isEmpty else {
            // No host to match a domain against (e.g. a non-web scheme) — open fresh.
            return .notFound
        }

        switch runner.openTabs(bundleID: bundleID, family: family) {
        case .denied:
            return .denied
        case .failed(let message):
            return .unsupported(message)
        case .tabs(let tabs):
            guard let match = tabs.first(where: { tab in
                guard let host = URL(string: tab.url)?.host else { return false }
                return BrowserDomain.hostsMatch(host, targetHost)
            }) else {
                return .notFound
            }
            let focused = runner.focusTab(
                bundleID: bundleID, family: family,
                windowIndex: match.windowIndex, tabIndex: match.tabIndex
            )
            return focused ? .surfaced : .notFound
        }
    }
}

/// Domain matching. Two hosts match when they are equal or one is a subdomain of
/// the other (a suffix at a label boundary) — so redirects that add or drop a
/// subdomain still surface, without matching unrelated domains that merely share
/// a trailing string. No Public Suffix List: the label-boundary rule already
/// prevents `foo.co.uk`/`bar.co.uk` from matching.
enum BrowserDomain {
    static func hostsMatch(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased()
        let y = b.lowercased()
        if x == y { return true }
        return x.hasSuffix("." + y) || y.hasSuffix("." + x)
    }
}

/// The AppleScript sources for enumerate/focus. Pure string building (no Apple
/// Events), so they are unit-tested directly.
enum BrowserTabScript {
    /// Emits one `windowIndex \t tabIndex \t url` line per open tab. URLs never
    /// contain a tab or linefeed, so the delimiters are unambiguous.
    static func enumerate(family: BrowserFamily, bundleID: String) -> String {
        let application = literal(bundleID)
        // Both families expose `windows` whose `tabs` carry a `URL`; only the
        // focus dialect differs, so enumeration is shared.
        //
        // The field/record separators MUST be bound outside the `tell` block:
        // inside it, `tab` resolves to the browser's `tab` *class* (coerced to the
        // text "tab"), not the ASCII-9 constant, which silently corrupts every
        // line. Bound here, `tab`/`linefeed` are the real characters our parser
        // splits on.
        return """
        set _fs to tab
        set _rs to linefeed
        set _out to ""
        tell application id \(application)
            set _w to 0
            repeat with _theWindow in windows
                set _w to _w + 1
                set _t to 0
                repeat with _theTab in tabs of _theWindow
                    set _t to _t + 1
                    set _out to _out & _w & _fs & _t & _fs & (URL of _theTab) & _rs
                end repeat
            end repeat
        end tell
        return _out
        """
    }

    static func focus(family: BrowserFamily, bundleID: String, windowIndex: Int, tabIndex: Int) -> String {
        let application = literal(bundleID)
        switch family {
        case .chromium:
            return """
            tell application id \(application)
                set active tab index of window \(windowIndex) to \(tabIndex)
                set index of window \(windowIndex) to 1
                activate
                return true
            end tell
            """
        case .safari:
            return """
            tell application id \(application)
                set current tab of window \(windowIndex) to tab \(tabIndex) of window \(windowIndex)
                set index of window \(windowIndex) to 1
                activate
                return true
            end tell
            """
        }
    }

    /// A raw string wrapped as an AppleScript double-quoted literal, escaping
    /// backslashes and quotes so a crafted bundle id cannot break out of it.
    static func literal(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Live runner: resolves the default browser via Launch Services and runs the
/// enumerate/focus scripts through `NSAppleScript`. Only a *running* browser is
/// scripted, so surfacing never launches an app as a side effect — a browser that
/// is not running enumerates to no tabs, and the caller opens fresh (which
/// launches it). Automation-denied maps to `denied`; every other script error
/// maps to `failed`, both of which the caller treats as "open fresh".
public struct SystemBrowserScriptRunner: BrowserScriptRunner {
    /// `errAEEventNotPermitted`: the user denied (or has not granted) Automation
    /// control of the target browser. The first real attempt triggers the system
    /// prompt; a denial surfaces here.
    private static let notPermitted = -1743

    public init() {}

    public func defaultBrowserBundleID() -> String? {
        guard
            let probe = URL(string: "https://example.com"),
            let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else {
            return nil
        }
        return Bundle(url: handler)?.bundleIdentifier
    }

    public func openTabs(bundleID: String, family: BrowserFamily) -> BrowserTabQuery {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            // Not running: nothing to surface. The caller opens fresh.
            return .tabs([])
        }
        let source = BrowserTabScript.enumerate(family: family, bundleID: bundleID)
        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not compile the browser enumeration script.")
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
            if number == Self.notPermitted {
                return .denied
            }
            let message = (errorInfo["NSAppleScriptErrorMessage"] as? String)
                ?? "The browser enumeration script failed (\(number))."
            return .failed(message)
        }
        return .tabs(Self.parseTabs(output.stringValue ?? ""))
    }

    public func focusTab(bundleID: String, family: BrowserFamily, windowIndex: Int, tabIndex: Int) -> Bool {
        let source = BrowserTabScript.focus(
            family: family, bundleID: bundleID, windowIndex: windowIndex, tabIndex: tabIndex
        )
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil { return false }
        return output.booleanValue
    }

    /// Parses the `windowIndex \t tabIndex \t url` lines emitted by the
    /// enumeration script, skipping any malformed line.
    static func parseTabs(_ raw: String) -> [BrowserTabRef] {
        raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let windowIndex = Int(parts[0]),
                  let tabIndex = Int(parts[1]) else { return nil }
            let url = String(parts[2])
            guard !url.isEmpty else { return nil }
            return BrowserTabRef(windowIndex: windowIndex, tabIndex: tabIndex, url: url)
        }
    }
}
#endif
