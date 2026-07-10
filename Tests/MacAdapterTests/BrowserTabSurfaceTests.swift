// Browser tab surfacing seam (NIC-145). The live AppleScript path is smoke-only
// on hardware; here we cover the pure, deterministic parts — family resolution,
// the focus-script builder (including URL escaping), and the dispatch/outcome
// mapping in `DefaultBrowserTabSurface` — through a fake runner so no Apple Event
// is ever sent. Gated so the Linux CI package build compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters

/// A scripted fake: returns a fixed default browser and focus result.
private struct FakeBrowserScriptRunner: BrowserScriptRunner {
    var bundleID: String?
    var result: BrowserFocusResult = .noMatch
    var recordedURLs: RecordingBox = RecordingBox()

    func defaultBrowserBundleID() -> String? { bundleID }

    func focusMatchingTab(url: URL, bundleID: String, family: BrowserFamily) -> BrowserFocusResult {
        recordedURLs.append(url)
        return result
    }
}

/// Thread-safe recorder so the fake stays `Sendable`.
private final class RecordingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func append(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
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

// MARK: - Focus script builder

@Test("the chromium script uses the active-tab-index dialect and embeds the escaped url")
func chromiumScript() {
    let url = URL(string: "https://github.com")!
    let source = BrowserFocusScript.source(url: url, bundleID: "com.google.Chrome", family: .chromium)
    #expect(source.contains("tell application id \"com.google.Chrome\""))
    #expect(source.contains("active tab index"))
    #expect(source.contains("set _target to \"https://github.com\""))
    // Trailing-slash tolerant so a browser-normalised URL still matches.
    #expect(source.contains("(_target & \"/\")"))
}

@Test("the safari script uses the current-tab dialect")
func safariScript() {
    let url = URL(string: "https://apple.com")!
    let source = BrowserFocusScript.source(url: url, bundleID: "com.apple.Safari", family: .safari)
    #expect(source.contains("tell application id \"com.apple.Safari\""))
    #expect(source.contains("set current tab of _w"))
}

@Test("a url containing quotes is escaped so it cannot break out of the applescript literal")
func urlEscaping() {
    // A crafted string with an embedded quote and backslash.
    let raw = "https://evil.example/\"\\onmouseover"
    let url = URL(string: "https://evil.example")!
    // Build a literal directly to assert escaping is total.
    let literal = BrowserFocusScript.literal(raw)
    #expect(literal == "\"https://evil.example/\\\"\\\\onmouseover\"")
    // And the builder path never emits a bare unescaped quote past the opening one.
    let source = BrowserFocusScript.source(url: url, bundleID: "com.google.Chrome", family: .chromium)
    #expect(source.contains("set _target to \"https://evil.example\""))
}

// MARK: - Dispatch + outcome mapping

@Test("no default browser is an unsupported outcome, and never scripts anything")
func noDefaultBrowser() async {
    let runner = FakeBrowserScriptRunner(bundleID: nil, result: .focused)
    let surface = DefaultBrowserTabSurface(runner: runner)
    let outcome = await surface.surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported when there is no default browser, got \(outcome).")
        return
    }
    #expect(runner.recordedURLs.all.isEmpty)
}

@Test("an unsupported default browser degrades to unsupported without scripting")
func unsupportedBrowser() async {
    let runner = FakeBrowserScriptRunner(bundleID: "org.mozilla.firefox", result: .focused)
    let surface = DefaultBrowserTabSurface(runner: runner)
    let outcome = await surface.surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported for Firefox, got \(outcome).")
        return
    }
    #expect(runner.recordedURLs.all.isEmpty)
}

@Test("a focused tab surfaces, and the resolved url reaches the runner")
func focusedSurfaces() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", result: .focused)
    let surface = DefaultBrowserTabSurface(runner: runner)
    let outcome = await surface.surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .surfaced)
    #expect(runner.recordedURLs.all == [URL(string: "https://github.com")!])
}

@Test("no matching tab reports notFound so the caller opens fresh")
func noMatchIsNotFound() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", result: .noMatch)
    let outcome = await DefaultBrowserTabSurface(runner: runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .notFound)
}

@Test("denied automation maps to denied")
func deniedMapsThrough() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", result: .denied)
    let outcome = await DefaultBrowserTabSurface(runner: runner).surface(url: URL(string: "https://github.com")!)
    #expect(outcome == .denied)
}

@Test("a script failure degrades to unsupported")
func failureDegrades() async {
    let runner = FakeBrowserScriptRunner(bundleID: "com.google.Chrome", result: .failed("boom"))
    let outcome = await DefaultBrowserTabSurface(runner: runner).surface(url: URL(string: "https://github.com")!)
    guard case .unsupported = outcome else {
        Issue.record("Expected unsupported for a script failure, got \(outcome).")
        return
    }
}
#endif
