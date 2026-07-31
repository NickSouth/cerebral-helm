// NIC-127 Increment 3: opening an https article link, preferring a running Chrome instance.
//
// Exercised through a fake `WorkspaceOpening` so no real browser launches; the live NSWorkspace
// path is covered by manual smoke on hardware. Gated so Linux CI compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

/// Records which open path the capability took: an "open with Chrome" document open, or a plain
/// default-browser openURL. Mutations run through non-async helpers so the lock is never taken
/// from an async context (Swift 6).
private final class RecordingWebWorkspace: WorkspaceOpening, @unchecked Sendable {
    let installed: [String: URL]
    private let lock = NSLock()
    private var withApp: [(paths: [URL], app: URL)] = []
    private var plain: [URL] = []

    init(installed: [String: URL]) { self.installed = installed }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? { installed[bundleID] }
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool { false }
    func openApplication(at url: URL) async throws {}
    func openApplication(at url: URL, arguments: [String]) async throws {}

    func openURL(_ url: URL) async throws { recordPlain(url) }
    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {
        recordWithApp(paths: paths, app: applicationURL)
    }

    private func recordPlain(_ url: URL) { lock.lock(); plain.append(url); lock.unlock() }
    private func recordWithApp(paths: [URL], app: URL) { lock.lock(); withApp.append((paths, app)); lock.unlock() }

    var chromeOpens: [(paths: [URL], app: URL)] { lock.lock(); defer { lock.unlock() }; return withApp }
    var defaultOpens: [URL] { lock.lock(); defer { lock.unlock() }; return plain }
}

private let webChromeBundleID = "com.google.Chrome"
private let webChromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")

@Test("validatedURL accepts an https URL with a host and preserves its query")
func webOpenValidatesHTTPS() throws {
    let url = try #require(NSWorkspaceWebOpenCapability.validatedURL("https://news.example.com/story?id=42"))
    #expect(url.scheme == "https")
    #expect(url.host == "news.example.com")
    #expect(url.absoluteString == "https://news.example.com/story?id=42")
}

@Test("validatedURL rejects non-https, host-less, and malformed links (feed data can't steer it)")
func webOpenRejectsNonHTTPS() {
    #expect(NSWorkspaceWebOpenCapability.validatedURL("http://example.com") == nil) // not https
    #expect(NSWorkspaceWebOpenCapability.validatedURL("ftp://example.com/f") == nil)
    #expect(NSWorkspaceWebOpenCapability.validatedURL("file:///etc/passwd") == nil)
    #expect(NSWorkspaceWebOpenCapability.validatedURL("javascript:alert(1)") == nil)
    #expect(NSWorkspaceWebOpenCapability.validatedURL("https://") == nil) // no host
    #expect(NSWorkspaceWebOpenCapability.validatedURL("not a url") == nil)
    #expect(NSWorkspaceWebOpenCapability.validatedURL("   ") == nil)
}

@Test("with Chrome installed the link opens as a document in Chrome (reusing a running instance)")
func webOpenPrefersChrome() async throws {
    let workspace = RecordingWebWorkspace(installed: [webChromeBundleID: webChromeURL])
    let capability = NSWorkspaceWebOpenCapability(workspace: workspace)

    let result = try await capability.open(url: "https://news.example.com/story")

    #expect(result.opened)
    #expect(result.url == "https://news.example.com/story")
    #expect(workspace.chromeOpens.count == 1)
    #expect(workspace.chromeOpens.first?.app == webChromeURL)
    #expect(workspace.defaultOpens.isEmpty) // did not fall back to the default browser
}

@Test("without Chrome the link falls back to the default browser")
func webOpenFallsBackWithoutChrome() async throws {
    let workspace = RecordingWebWorkspace(installed: [:]) // Chrome not installed
    let capability = NSWorkspaceWebOpenCapability(workspace: workspace)

    let result = try await capability.open(url: "https://news.example.com/story")

    #expect(result.opened)
    #expect(workspace.defaultOpens.count == 1)
    #expect(workspace.chromeOpens.isEmpty)
}

@Test("a non-https link is refused rather than opened in any browser")
func webOpenRefusesNonHTTPS() async {
    let workspace = RecordingWebWorkspace(installed: [webChromeBundleID: webChromeURL])
    let capability = NSWorkspaceWebOpenCapability(workspace: workspace)
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.open(url: "http://example.com/insecure")
    }
    #expect(workspace.chromeOpens.isEmpty)
    #expect(workspace.defaultOpens.isEmpty)
}
#endif
