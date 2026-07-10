// Browser tab surfacing seam (NIC-145). The live AppleScript path is smoke-only
// on hardware; here we cover the pure, deterministic parts — family resolution,
// domain matching, the enumerate/focus script builders, the tab-list parser, and
// the dispatch/outcome mapping in `DefaultBrowserTabSurface` — through a fake
// runner so no Apple Event is ever sent. Gated so the Linux CI package build
// compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters

/// A scripted fake: returns a fixed default browser, tab list, and focus result,
/// recording what it was asked to focus.
private struct FakeBrowserScriptRunner: BrowserScriptRunner {
    var bundleID: String?
    var query: BrowserTabQuery = .tabs([])
    var focusSucceeds: Bool = true
    var focusCalls: FocusBox = FocusBox()

    func defaultBrowserBundleID() -> String? { bundleID }

    func openTabs(bundleID: String, family: BrowserFamily) -> BrowserTabQuery { query }

    func focusTab(bundleID: String, family: BrowserFamily, windowIndex: Int, tabIndex: Int) -> Bool {
        focusCalls.record(windowIndex: windowIndex, tabIndex: tabIndex)
        return focusSucceeds
    }
}

/// Thread-safe recorder so the fake stays `Sendable`.
private final class FocusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(Int, Int)] = []
    func record(windowIndex: Int, tabIndex: Int) { lock.lock(); calls.append((windowIndex, tabIndex)); lock.unlock() }
    var all: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return calls }
}

private func surface(_ runner: FakeBrowserScriptRunner) -> DefaultBrowserTabSurface {
    DefaultBrowserTabSurface(runner: runner)
}

// MARK: - Family resolution

@Test("browser families map from known bundle ids, and unsupported browsers are nil")
func familyResolution() {
    #expect(BrowserFamily.forBundleID("com.apple.Safari") == .safari)
    #expect(BrowserFamily.forBundleID("com.google.Chrome") == .chromium)
    #expect(BrowserFamily.forBundleID("com.brave.Browser") == .chromium)
    #expect(BrowserFamily.forBundleID("com.microsoft.edgemac") == .chromium)
    // Firefox and Arc expose no supported per-tab URL control → open fresh.
    #expect(BrowserFamily.forBundleID("org.mozilla.firefox") == nil)
    #expect(BrowserFamily.forBundleID("company.thebrowser.Browser") == nil)
}

// MARK: - Domain matching

@Test("hosts match when equal or a subdomain either way, but not unrelated look-alikes")
func domainMatching() {
    #expect(BrowserDomain.hostsMatch("github.com", "github.com"))
    // Redirect added a subdomain.
    #expect(BrowserDomain.hostsMatch("www.github.com", "github.com"))
    #expect(BrowserDomain.hostsMatch("app.github.com", "github.com"))
    // Pinned with a subdomain, redirect dropped it.
    #expect(BrowserDomain.hostsMatch("github.com", "www.github.com"))
    // Case-insensitive.
    #expect(BrowserDomain.hostsMatch("GitHub.com", "github.com"))
    // Look-alikes that merely share a trailing string must not match.
    #expect(!BrowserDomain.hostsMatch("notgithub.com", "github.com"))
    #expect(!BrowserDomain.hostsMatch("github.com.evil.com", "github.com"))
    // Sibling subdomains of a shared suffix do not match each other.
    #expect(!BrowserDomain.hostsMatch("foo.co.uk", "bar.co.uk"))
}

// MARK: - Script builders + parser

@Test("the enumerate script walks windows and tabs and emits delimited url lines")
func enumerateScript() {
    let source = BrowserTabScript.enumerate(family: .chromium, bundleID: "com.google.Chrome")
    #expect(source.contains("tell application id \"com.google.Chrome\""))
    #expect(source.contains("repeat with _theTab in tabs of _theWindow"))
    #expect(source.contains("URL of _theTab"))
}

@Test("the enumerate script binds tab/linefeed OUTSIDE the tell block, so they are real characters")
func enumerateDelimitersAreHoisted() {
    let source = BrowserTabScript.enumerate(family: .chromium, bundleID: "com.google.Chrome")
    // Regression guard (NIC-145): inside a browser `tell` block, `tab`/`linefeed`
    // resolve to the app's `tab` class (the text "tab"), corrupting every line.
    // They must be bound before the tell, and the loop must use the bound vars.
    guard let bindIndex = source.range(of: "set _fs to tab"),
          let tellIndex = source.range(of: "tell application id") else {
        Issue.record("Expected the delimiter binding and the tell block."); return
    }
    #expect(bindIndex.lowerBound < tellIndex.lowerBound)
    #expect(source.contains("set _rs to linefeed"))
    #expect(source.contains("_w & _fs & _t & _fs & (URL of _theTab) & _rs"))
    // The corrupting form must never appear.
    #expect(!source.contains("& tab &"))
    #expect(!source.contains("& linefeed"))
}

@Test("the focus script uses the family dialect and the given indices")
func focusScript() {
    let chromium = BrowserTabScript.focus(family: .chromium, bundleID: "com.google.Chrome", windowIndex: 2, tabIndex: 5)
    #expect(chromium.contains("set active tab index of window 2 to 5"))
    #expect(chromium.contains("set index of window 2 to 1"))

    let safari = BrowserTabScript.focus(family: .safari, bundleID: "com.apple.Safari", windowIndex: 1, tabIndex: 3)
    #expect(safari.contains("set current tab of window 1 to tab 3 of window 1"))
}

@Test("a bundle id containing quotes is escaped so it cannot break out of the literal")
func bundleIDEscaping() {
    let literal = BrowserTabScript.literal("a\"b\\c")
    #expect(literal == "\"a\\\"b\\\\c\"")
}

@Test("the tab parser reads well-formed lines and skips malformed ones")
func tabParsing() {
    let raw = "1\t1\thttps://github.com/\n1\t2\thttps://apple.com/\nbad-line\n2\t1\thttps://example.com/"
    let tabs = SystemBrowserScriptRunner.parseTabs(raw)
    #expect(tabs == [
        BrowserTabRef(windowIndex: 1, tabIndex: 1, url: "https://github.com/"),
        BrowserTabRef(windowIndex: 1, tabIndex: 2, url: "https://apple.com/"),
        BrowserTabRef(windowIndex: 2, tabIndex: 1, url: "https://example.com/"),
    ])
}

// MARK: - Dispatch + outcome mapping

@Test("no default browser is an unsupported outcome, and never enumerates")
func noDefaultBrowser() async {
    let runner = FakeBrowserScriptRunner(bundleID: nil)
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported when there is no default browser, got \(outcome).")
        return
    }
    #expect(runner.focusCalls.all.isEmpty)
}

@Test("an unsupported default browser degrades to unsupported")
func unsupportedBrowser() async {
    let runner = FakeBrowserScriptRunner(bundleID: "org.mozilla.firefox")
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported for Firefox, got \(outcome).")
        return
    }
}

@Test("a tab on the same domain (redirected path/subdomain) is surfaced and focused by index")
func domainTabSurfaces() async {
    // Pinned github.com; the open tab redirected to a deep path on a subdomain.
    let runner = FakeBrowserScriptRunner(
        bundleID: "com.google.Chrome",
        query: .tabs([
            BrowserTabRef(windowIndex: 1, tabIndex: 1, url: "https://apple.com/"),
            BrowserTabRef(windowIndex: 1, tabIndex: 2, url: "https://www.github.com/dashboard/feed"),
        ])
    )
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .surfaced)
    #expect(runner.focusCalls.all.map { [$0.0, $0.1] } == [[1, 2]])
}

@Test("no tab on the domain reports notFound so the caller opens fresh")
func noDomainMatchIsNotFound() async {
    let runner = FakeBrowserScriptRunner(
        bundleID: "com.google.Chrome",
        query: .tabs([BrowserTabRef(windowIndex: 1, tabIndex: 1, url: "https://apple.com/")])
    )
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .notFound)
    #expect(runner.focusCalls.all.isEmpty)
}

@Test("a matched tab that fails to focus (window vanished) degrades to notFound")
func focusFailureIsNotFound() async {
    let runner = FakeBrowserScriptRunner(
        bundleID: "com.google.Chrome",
        query: .tabs([BrowserTabRef(windowIndex: 1, tabIndex: 1, url: "https://github.com/")]),
        focusSucceeds: false
    )
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .notFound)
    #expect(runner.focusCalls.all.map { [$0.0, $0.1] } == [[1, 1]])
}

@Test("denied automation maps to denied")
func deniedMapsThrough() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", query: .denied)
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .denied)
}

@Test("an enumeration failure degrades to unsupported")
func failureDegrades() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", query: .failed("boom"))
    let outcome = await surface(runner).surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported for an enumeration failure, got \(outcome).")
        return
    }
}
#endif
