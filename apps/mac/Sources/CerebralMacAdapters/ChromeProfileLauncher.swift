// Chrome profile window tracking (NIC-151 follow-up, Nick's design). macOS gives a
// `--profile-directory` launch no handle to the window it opens, and Chrome exposes
// no per-window profile to AppleScript — so relaunching a profile opens a *new*
// window every time (the reopening Nick hit), and a URL handed to a running Chrome
// as a document lands in whatever profile is frontmost.
//
// The insight: we don't need Chrome to tell us the profile — we launched the window,
// so we can remember it. When we open a profile and have no live window recorded for
// it, we launch one and capture the new (frontmost) window's id; that id → profile is
// held in memory for the app's lifetime. On the next open for that profile we focus
// the recorded window (and open the URL as a tab in it) instead of launching a
// duplicate. Closed windows are pruned by intersecting the recorded ids with the
// live window list, so a stale id never matches.
//
// Two seams, mirroring `BrowserTabSurface`: `ChromeWindowScripting` (the AppleScript
// primitives — covered by manual smoke on hardware) and `ChromeProfileLauncher` (the
// pure reuse-vs-launch decision + registry — unit-tested with a fake). Compiled empty
// off Apple platforms so the package graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// The AppleScript primitives for reading and steering Chrome's windows by id. A
/// window `id` is a stable integer for the window's lifetime, usable both to
/// discover a freshly launched window and to focus/target it later.
public protocol ChromeWindowScripting: Sendable {
    /// The ids of Chrome's open windows. Empty when Chrome isn't running (never
    /// launches it as a side effect) or Automation is denied.
    func openWindowIDs() -> [Int]
    /// The id of Chrome's frontmost window, or nil.
    func frontWindowID() -> Int?
    /// Bring the window with `id` to the front and activate Chrome. `false` when it
    /// could not (e.g. the window closed).
    func focusWindow(id: Int) -> Bool
    /// Open `url` as a new tab in the window with `id`. `false` on failure.
    func openTab(inWindowID id: Int, url: URL) -> Bool
    /// The open tabs of the window with `id`, as (1-based tab index, url string) —
    /// for profile-scoped surfacing. Empty when the window is gone or on error.
    func tabs(inWindowID id: Int) -> [(index: Int, url: String)]
    /// Make the tab at `tabIndex` active in the window with `id` and bring it to the
    /// front. `false` on failure.
    func focusTab(windowID id: Int, tabIndex: Int) -> Bool
}

/// The bucket a Chrome window belongs to (NIC-143 follow-up, "each mode its own Chrome
/// window"): a window is keyed by BOTH the active mode and the Chrome profile, so a mode's
/// tabs stay on that mode's window — "Developer + Work" and "Entertainment + Work" get
/// separate windows, and a profile-less open keys by mode alone. `mode`/`profile` are
/// `nil` when absent (no active mode / the default profile).
struct ChromeWindowKey: Hashable, Sendable {
    let mode: String?
    let profile: String?
}

/// In-memory window-bucket → Chrome window id map, held for the app's lifetime.
/// Thread-safe; mirrors the `PolicyOverridesBox` locking pattern.
final class ChromeProfileWindowRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var windowByKey: [ChromeWindowKey: Int] = [:]

    func windowID(for key: ChromeWindowKey) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return windowByKey[key]
    }

    func record(key: ChromeWindowKey, windowID: Int) {
        lock.lock(); defer { lock.unlock() }
        windowByKey[key] = windowID
    }

    /// Drop any recorded window whose id is no longer live, so a closed window never
    /// masquerades as an open bucket.
    func prune(liveIDs: Set<Int>) {
        lock.lock(); defer { lock.unlock() }
        windowByKey = windowByKey.filter { liveIDs.contains($0.value) }
    }
}

/// Opens Google Chrome in a specific profile, reusing the profile's existing window
/// when one is live and launching (then remembering) a new one otherwise.
public final class ChromeProfileLauncher: @unchecked Sendable {
    /// What happened, so the caller can report opened-vs-surfaced honestly.
    public enum Outcome: Equatable, Sendable {
        /// A tab already on the URL's domain, in the profile's own window, was focused.
        case surfacedExistingTab
        /// The URL was opened as a new tab in the profile's existing window.
        case openedTab
        /// The profile's existing window was focused (bare Chrome, no URL).
        case focusedWindow
        /// Chrome was launched fresh in the profile.
        case launched
    }

    private let chromeBundleID: String
    private let workspace: any WorkspaceOpening
    private let scripting: any ChromeWindowScripting
    private let registry = ChromeProfileWindowRegistry()
    /// Waits for a freshly launched window to appear before capturing its id. Injected
    /// so tests run without real delay.
    private let settle: @Sendable () async -> Void

    public init(
        chromeBundleID: String = "com.google.Chrome",
        workspace: any WorkspaceOpening,
        scripting: any ChromeWindowScripting = SystemChromeWindowScripting(),
        settle: @escaping @Sendable () async -> Void = { try? await Task.sleep(nanoseconds: 700_000_000) }
    ) {
        self.chromeBundleID = chromeBundleID
        self.workspace = workspace
        self.scripting = scripting
        self.settle = settle
    }

    /// Profile-only convenience (mode-agnostic bucket) — kept for callers/tests that
    /// don't scope by mode.
    @discardableResult
    public func open(profile: String, url: URL?) async throws -> Outcome {
        try await open(mode: nil, profile: profile, url: url)
    }

    /// Focus the bucket's window (opening `url` as a tab there when given), or launch
    /// Chrome for that bucket and remember the new window. The bucket is `(mode, profile)`,
    /// so each mode keeps its own Chrome window (NIC-143 follow-up); the launch forces a
    /// distinct window with `--new-window`. Throws `notFound` when Chrome isn't installed.
    @discardableResult
    public func open(mode: String?, profile: String?, url: URL?) async throws -> Outcome {
        let key = ChromeWindowKey(mode: mode, profile: profile)
        // Prune closed windows so a stale recorded id can't match.
        let liveIDs = Set(scripting.openWindowIDs())
        registry.prune(liveIDs: liveIDs)
        if let windowID = registry.windowID(for: key), liveIDs.contains(windowID) {
            // The bucket already has a live window — reuse it, never a duplicate.
            guard let url else {
                // Bare Chrome: just bring the profile window forward.
                _ = scripting.focusWindow(id: windowID)
                return .focusedWindow
            }
            // Profile-SCOPED surfacing (Nick's requirement): only tabs in THIS
            // profile's window are considered, so a matching tab in a different
            // profile is never surfaced. Match by domain (any route/subdomain of the
            // same host), the same rule the global surfacer uses.
            if let host = url.host, !host.isEmpty,
               let match = scripting.tabs(inWindowID: windowID).first(where: { tab in
                   guard let tabHost = URL(string: tab.url)?.host else { return false }
                   return BrowserDomain.hostsMatch(tabHost, host)
               }) {
                _ = scripting.focusTab(windowID: windowID, tabIndex: match.index)
                return .surfacedExistingTab
            }
            // No matching tab in the profile window — open one there.
            _ = scripting.openTab(inWindowID: windowID, url: url)
            _ = scripting.focusWindow(id: windowID)
            return .openedTab
        }

        // No live window for this bucket: launch a NEW Chrome window for it. `--new-window`
        // forces a distinct window so a mode never shares another mode's (or the user's
        // manual) window; the profile flag scopes it, and the URL rides as an argument so
        // Chrome routes it into the profile.
        guard let chromeURL = workspace.installedApplicationURL(forBundleIdentifier: chromeBundleID) else {
            throw NativeCapabilityError.notFound(
                "Google Chrome isn't installed, so it can't be opened. Install Chrome, or remove the profile from the reference."
            )
        }
        var arguments = ["--new-window"]
        if let profile { arguments.append("--profile-directory=\(profile)") }
        if let url { arguments.append(url.absoluteString) }
        try await workspace.openApplication(at: chromeURL, arguments: arguments)

        // Capture the bucket's window so the next open reuses (and surfaces into) it.
        if let window = await capturedProfileWindow(before: liveIDs, url: url) {
            registry.record(key: key, windowID: window)
        }
        return .launched
    }

    /// The window our launch targeted, identified robustly. A launch forwards to a
    /// running Chrome, during which its AppleScript connection is briefly invalid and
    /// the new tab/window hasn't materialized — so this polls (`settle` between tries)
    /// and, crucially, identifies a **pre-existing** profile window by the tab it just
    /// received, not only by being new. Order of preference:
    ///   1. a genuinely new window (unambiguously the profile's);
    ///   2. the front window, once it actually holds the opened URL (Chrome brings the
    ///      profile's window frontmost after the launch) — this is the case that a
    ///      pre-existing profile window falls into;
    ///   3. any window holding the URL;
    ///   4. the front window as a last resort (bare Chrome, or the URL never appeared).
    private func capturedProfileWindow(before old: Set<Int>, url: URL?) async -> Int? {
        for _ in 0..<6 {
            await settle()
            let after = scripting.openWindowIDs()
            guard !after.isEmpty else { continue } // connection-invalid / mid-launch — retry
            if let newWindow = after.first(where: { !old.contains($0) }) {
                return newWindow
            }
            guard let host = url?.host, !host.isEmpty else {
                return scripting.frontWindowID() // bare Chrome: reused window is frontmost
            }
            if let front = scripting.frontWindowID(), windowHolds(host: host, windowID: front) {
                return front
            }
            if let match = after.first(where: { windowHolds(host: host, windowID: $0) }) {
                return match
            }
            // The tab hasn't appeared yet — retry.
        }
        return scripting.frontWindowID()
    }

    /// Whether the window with `id` has a tab on `host` (any route/subdomain).
    private func windowHolds(host: String, windowID id: Int) -> Bool {
        scripting.tabs(inWindowID: id).contains { tab in
            guard let tabHost = URL(string: tab.url)?.host else { return false }
            return BrowserDomain.hostsMatch(tabHost, host)
        }
    }
}

/// Live scripting via `NSAppleScript`, only touching a *running* Chrome (a `tell`
/// against a non-running app would launch it, so every read guards on running first).
/// Automation-denied or any script error degrades to the safe default (no ids / false),
/// which makes the launcher fall back to a plain launch — today's behavior.
public struct SystemChromeWindowScripting: ChromeWindowScripting {
    private static let chromeBundleID = "com.google.Chrome"

    public init() {}

    private var chromeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).isEmpty
    }

    public func openWindowIDs() -> [Int] {
        guard chromeRunning else { return [] }
        let source = """
        tell application id "\(Self.chromeBundleID)"
            set _ids to {}
            repeat with _w in windows
                set end of _ids to id of _w
            end repeat
            return _ids
        end tell
        """
        guard let output = run(source) else { return [] }
        return Self.integers(from: output)
    }

    public func frontWindowID() -> Int? {
        guard chromeRunning else { return nil }
        let source = """
        tell application id "\(Self.chromeBundleID)"
            if (count of windows) is 0 then return -1
            return id of front window
        end tell
        """
        guard let output = run(source) else { return nil }
        let value = Int(output.int32Value)
        return value >= 0 ? value : nil
    }

    public func focusWindow(id: Int) -> Bool {
        guard chromeRunning else { return false }
        let source = """
        tell application id "\(Self.chromeBundleID)"
            set _w to (first window whose id is \(id))
            set index of _w to 1
            activate
            return true
        end tell
        """
        return run(source)?.booleanValue ?? false
    }

    public func openTab(inWindowID id: Int, url: URL) -> Bool {
        guard chromeRunning else { return false }
        let literal = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application id "\(Self.chromeBundleID)"
            tell (first window whose id is \(id)) to make new tab with properties {URL:"\(literal)"}
            return true
        end tell
        """
        return run(source)?.booleanValue ?? false
    }

    public func tabs(inWindowID id: Int) -> [(index: Int, url: String)] {
        guard chromeRunning else { return [] }
        // One `index \t url` line per tab. The field/record separators MUST be bound
        // OUTSIDE the tell block: inside it, `tab` resolves to Chrome's `tab` *class*
        // (coerced to the text "tab"), not the ASCII-9 character, which silently
        // corrupts every line — the exact gotcha the global surfacer documents.
        let source = """
        set _fs to tab
        set _rs to linefeed
        set _out to ""
        tell application id "\(Self.chromeBundleID)"
            set _t to 0
            repeat with _tab in tabs of (first window whose id is \(id))
                set _t to _t + 1
                set _out to _out & _t & _fs & (URL of _tab) & _rs
            end repeat
        end tell
        return _out
        """
        guard let output = run(source)?.stringValue else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let index = Int(parts[0]) else { return nil }
            let url = String(parts[1])
            return url.isEmpty ? nil : (index, url)
        }
    }

    public func focusTab(windowID id: Int, tabIndex: Int) -> Bool {
        guard chromeRunning else { return false }
        let source = """
        tell application id "\(Self.chromeBundleID)"
            set active tab index of (first window whose id is \(id)) to \(tabIndex)
            set index of (first window whose id is \(id)) to 1
            activate
            return true
        end tell
        """
        return run(source)?.booleanValue ?? false
    }

    /// Runs a script, returning its result descriptor, or nil on any error (compile,
    /// runtime, or Automation denied) — the caller treats nil as the safe default.
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? output : nil
    }

    /// Extracts integers from a descriptor that may be an AppleScript list (many
    /// windows) or a single integer (one window).
    static func integers(from descriptor: NSAppleEventDescriptor) -> [Int] {
        let count = descriptor.numberOfItems
        if count == 0 {
            let single = Int(descriptor.int32Value)
            return single != 0 ? [single] : []
        }
        var result: [Int] = []
        for index in 1...count {
            if let item = descriptor.atIndex(index) {
                result.append(Int(item.int32Value))
            }
        }
        return result
    }
}
#endif
