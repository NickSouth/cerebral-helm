// Browser tab surfacing (NIC-145). When CH re-triggers a URL it already opened
// in the current mode, the URL adapter asks this seam to focus the *existing*
// browser tab instead of opening a duplicate. macOS gives `NSWorkspace.open` no
// tab handle, so surfacing is done through AppleScript against the running
// default browser; the dialect differs per browser family.
//
// Two layers, mirroring `AXWindowSurface`/`AXWindowCapability`:
//   * `BrowserScriptRunner` — the low-level native primitives (default-browser
//     resolution + AppleScript execution). Its live implementation is covered by
//     manual smoke on hardware; contract tests never send Apple Events.
//   * `DefaultBrowserTabSurface` — the family dispatch and outcome mapping, which
//     are pure and unit-tested with a fake runner.
//
// Every non-`surfaced` outcome means "the caller should just open fresh" — a
// deliberately graceful degradation (unsupported browser, no match, or denied
// Automation permission never errors; NIC-145 owner decision: no permission
// gate on `url.open`). This target compiles empty on non-Apple platforms so the
// package graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation

/// The result of asking to surface a URL's tab in the default browser.
public enum BrowserSurfaceOutcome: Equatable, Sendable {
    /// An existing tab CH opened for this URL was focused; do not open a new one.
    case surfaced
    /// The browser is scriptable but no open tab matches; open fresh.
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

/// The outcome of the low-level focus attempt against a specific running browser.
public enum BrowserFocusResult: Equatable, Sendable {
    /// A matching tab was found and raised.
    case focused
    /// The browser was scriptable and ran, but no tab matched (or it was not running).
    case noMatch
    /// Automation permission for the browser was denied.
    case denied
    /// The focus script failed unexpectedly (compile/runtime error).
    case failed(String)
}

/// Low-level seam over the AppleScript bridge, so the dispatch/outcome logic is
/// testable with a fake while the live implementation touches real Apple Events.
public protocol BrowserScriptRunner: Sendable {
    /// Bundle id of the default handler for `https`, or `nil` when none resolves.
    func defaultBrowserBundleID() -> String?
    /// Focus the first tab showing `url` in the running app with `bundleID`,
    /// using the `family` dialect. Never launches the browser.
    func focusMatchingTab(url: URL, bundleID: String, family: BrowserFamily) -> BrowserFocusResult
}

/// Focus an existing browser tab for a URL, or report why it could not.
public protocol BrowserTabSurface: Sendable {
    func surface(url: URL) async -> BrowserSurfaceOutcome
}

/// Resolves the default browser, picks the scripting dialect, and maps the
/// low-level result to a surface outcome. Pure aside from the injected runner.
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
        switch runner.focusMatchingTab(url: url, bundleID: bundleID, family: family) {
        case .focused:
            return .surfaced
        case .noMatch:
            return .notFound
        case .denied:
            return .denied
        case .failed(let message):
            return .unsupported(message)
        }
    }
}

/// The AppleScript source for a focus attempt. Pure string building (no Apple
/// Events), so it is unit-tested directly.
enum BrowserFocusScript {
    static func source(url: URL, bundleID: String, family: BrowserFamily) -> String {
        let application = literal(bundleID)
        let target = literal(url.absoluteString)
        switch family {
        case .chromium:
            // Chromium browsers expose 0-based windows of 1-based `tabs` with a
            // settable `active tab index`. Match the URL as opened, tolerating a
            // trailing slash the browser may have normalised in.
            return """
            tell application id \(application)
                set _target to \(target)
                repeat with _w in windows
                    set _i to 0
                    repeat with _t in tabs of _w
                        set _i to _i + 1
                        set _u to URL of _t
                        if _u is _target or _u is (_target & "/") then
                            set active tab index of _w to _i
                            set index of _w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
                return false
            end tell
            """
        case .safari:
            // Safari exposes `tabs` of each window and a settable `current tab`.
            return """
            tell application id \(application)
                set _target to \(target)
                repeat with _w in windows
                    set _tabs to tabs of _w
                    repeat with _k from 1 to (count of _tabs)
                        set _t to item _k of _tabs
                        set _u to URL of _t
                        if _u is _target or _u is (_target & "/") then
                            set current tab of _w to _t
                            set index of _w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
                return false
            end tell
            """
        }
    }

    /// A raw string wrapped as an AppleScript double-quoted literal, escaping
    /// backslashes and quotes so a crafted URL cannot break out of the string.
    static func literal(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// Live runner: resolves the default browser via Launch Services and executes
/// the focus script through `NSAppleScript`. Only a *running* browser is
/// scripted, so surfacing never launches an app as a side effect — a browser
/// that is not running reports `noMatch`, and the caller opens fresh (which
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

    public func focusMatchingTab(url: URL, bundleID: String, family: BrowserFamily) -> BrowserFocusResult {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            // Not running: nothing to surface. The caller opens fresh.
            return .noMatch
        }
        let source = BrowserFocusScript.source(url: url, bundleID: bundleID, family: family)
        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not compile the browser focus script.")
        }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
            if number == Self.notPermitted {
                return .denied
            }
            let message = (errorInfo["NSAppleScriptErrorMessage"] as? String)
                ?? "The browser focus script failed (\(number))."
            return .failed(message)
        }
        return output.booleanValue ? .focused : .noMatch
    }
}
#endif
