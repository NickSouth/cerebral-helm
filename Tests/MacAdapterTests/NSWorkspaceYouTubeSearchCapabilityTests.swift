// Quick actions phase 4, action 1: opening a YouTube search, preferring a running Chrome instance.
//
// Exercised through a fake `WorkspaceOpening` so no real browser launches; the live NSWorkspace
// path is covered by manual smoke on hardware. Gated so Linux CI compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

/// Records which open path the capability took. Mirrors the Google adapter's recorder; mutations
/// run through non-async helpers so the lock is never taken from an async context (Swift 6).
private final class RecordingYouTubeWorkspace: WorkspaceOpening, @unchecked Sendable {
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

private let chromeBundleID = "com.google.Chrome"
private let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")

@Test("the search URL fixes the youtube.com host and percent-encodes the query")
func youtubeSearchURLIsHostFixed() throws {
    let url = try #require(NSWorkspaceYouTubeSearchCapability.searchURL(query: "Dune: Part Two trailer"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.scheme == "https")
    #expect(components.host == "www.youtube.com")
    #expect(components.path == "/results")
    let queryValue = components.queryItems?.first(where: { $0.name == "search_query" })?.value
    #expect(queryValue == "Dune: Part Two trailer")
    // Spaces are percent-encoded in the raw URL, so the query can never split it.
    #expect(url.absoluteString.contains("%20"))
    #expect(!url.absoluteString.contains("Part Two"))
}

@Test("a query that looks like a URL is still only a query — it cannot redirect the destination")
func youtubeSearchQueryCannotChooseTheHost() throws {
    // The safety property the separate-adapter-per-host design exists to guarantee.
    let url = try #require(NSWorkspaceYouTubeSearchCapability.searchURL(query: "https://evil.example/#x"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "www.youtube.com")
    #expect(!url.absoluteString.hasPrefix("https://evil.example"))
}

@Test("with Chrome installed the search opens as a document in Chrome (reusing a running instance)")
func youtubeSearchPrefersChrome() async throws {
    let workspace = RecordingYouTubeWorkspace(installed: [chromeBundleID: chromeURL])
    let capability = NSWorkspaceYouTubeSearchCapability(workspace: workspace)

    let result = try await capability.search(query: "how to poach an egg")

    #expect(result.opened)
    #expect(result.resolvedURL.hasPrefix("https://www.youtube.com/results?search_query="))
    #expect(workspace.chromeOpens.count == 1)
    #expect(workspace.chromeOpens.first?.app == chromeURL)
    #expect(workspace.defaultOpens.isEmpty) // did not fall back to the default browser
}

@Test("without Chrome the search falls back to the default browser")
func youtubeSearchFallsBackWithoutChrome() async throws {
    let workspace = RecordingYouTubeWorkspace(installed: [:]) // Chrome not installed
    let capability = NSWorkspaceYouTubeSearchCapability(workspace: workspace)

    let result = try await capability.search(query: "guitar tuning")

    #expect(result.opened)
    #expect(workspace.defaultOpens.count == 1)
    #expect(workspace.chromeOpens.isEmpty)
}

@Test("a blank query is rejected rather than opening an empty search")
func youtubeSearchRejectsBlankQuery() async {
    let workspace = RecordingYouTubeWorkspace(installed: [chromeBundleID: chromeURL])
    let capability = NSWorkspaceYouTubeSearchCapability(workspace: workspace)
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.search(query: "   ")
    }
}
#endif
