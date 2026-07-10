// NIC-79 (MAC-ADAPTER-1): NSWorkspace app.open / url.open adapters.
//
// The adapters are exercised through a fake `WorkspaceOpening` so no real
// application ever launches in a test run; the live NSWorkspace path is covered
// by manual smoke on hardware. Gated so the Linux CI package build compiles this
// target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralCore
import CerebralMacAdapters
import CerebralTools

/// A recording fake: `installed` maps bundle ids to app URLs; `running` lists
/// bundle ids reported as running; `failure` makes open calls throw.
private final class FakeWorkspace: WorkspaceOpening, @unchecked Sendable {
    struct OpenFailure: Error, LocalizedError {
        var errorDescription: String? { "simulated launch failure" }
    }

    let installed: [String: URL]
    let running: Set<String>
    let failsToOpen: Bool

    private let lock = NSLock()
    private var openedApplications: [URL] = []
    private var openedURLs: [URL] = []

    init(installed: [String: URL] = [:], running: Set<String> = [], failsToOpen: Bool = false) {
        self.installed = installed
        self.running = running
        self.failsToOpen = failsToOpen
    }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? {
        installed[bundleID]
    }

    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool {
        running.contains(bundleID)
    }

    func openApplication(at url: URL) async throws {
        if failsToOpen { throw OpenFailure() }
        record(url, into: \.openedApplications)
    }

    func openURL(_ url: URL) async throws {
        if failsToOpen { throw OpenFailure() }
        record(url, into: \.openedURLs)
    }

    private func record(_ url: URL, into keyPath: ReferenceWritableKeyPath<FakeWorkspace, [URL]>) {
        lock.lock()
        self[keyPath: keyPath].append(url)
        lock.unlock()
    }

    var applicationOpens: [URL] {
        lock.lock(); defer { lock.unlock() }
        return openedApplications
    }

    var urlOpens: [URL] {
        lock.lock(); defer { lock.unlock() }
        return openedURLs
    }
}

private let vscodeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

private func workspace(running: Set<String> = [], failsToOpen: Bool = false) -> FakeWorkspace {
    FakeWorkspace(
        installed: ["com.microsoft.VSCode": vscodeURL],
        running: running,
        failsToOpen: failsToOpen
    )
}

private func appCapability(_ fake: FakeWorkspace) -> NSWorkspaceAppCapability {
    NSWorkspaceAppCapability(apps: ["vscode": "com.microsoft.VSCode"], workspace: fake)
}

private func urlCapability(_ fake: FakeWorkspace, urls: [String: String] = ["github": "https://github.com"]) -> NSWorkspaceURLCapability {
    NSWorkspaceURLCapability(urls: urls, workspace: fake)
}

// MARK: - app.open

@Test("a configured, installed app opens through the workspace and reports launched")
func configuredAppOpens() async throws {
    let fake = workspace()
    let result = try await appCapability(fake).open(appID: "vscode")

    #expect(result == AppOpenResult(appID: "vscode", launched: true, alreadyRunning: false))
    #expect(fake.applicationOpens == [vscodeURL])
}

@Test("an already-running app is activated and reported alreadyRunning, not launched")
func alreadyRunningAppIsActivated() async throws {
    let fake = workspace(running: ["com.microsoft.VSCode"])
    let result = try await appCapability(fake).open(appID: "vscode")

    #expect(result.alreadyRunning)
    #expect(!result.launched)
    // Activation still goes through the workspace so the app comes to front.
    #expect(fake.applicationOpens == [vscodeURL])
}

@Test("an unconfigured app reference is notFound with settings remediation, and never reaches the workspace")
func unconfiguredAppIsNotFound() async throws {
    let fake = workspace()
    do {
        _ = try await appCapability(fake).open(appID: "photoshop")
        Issue.record("Expected notFound for an unconfigured reference")
    } catch let error as NativeCapabilityError {
        guard case let .notFound(message) = error else {
            Issue.record("Expected .notFound, got \(error)"); return
        }
        #expect(message.contains("Settings"))
    }
    #expect(fake.applicationOpens.isEmpty)
}

@Test("a configured app that is not installed is notFound with settings remediation")
func missingInstalledAppIsNotFound() async throws {
    let fake = FakeWorkspace(installed: [:])
    do {
        _ = try await appCapability(fake).open(appID: "vscode")
        Issue.record("Expected notFound for a missing application")
    } catch let error as NativeCapabilityError {
        guard case let .notFound(message) = error else {
            Issue.record("Expected .notFound, got \(error)"); return
        }
        #expect(message.contains("com.microsoft.VSCode"))
        #expect(message.contains("Settings"))
    }
}

@Test("a workspace launch failure surfaces as adapterFailure with the platform detail in the message")
func launchFailureIsAdapterFailure() async throws {
    do {
        _ = try await appCapability(workspace(failsToOpen: true)).open(appID: "vscode")
        Issue.record("Expected adapterFailure")
    } catch let error as NativeCapabilityError {
        guard case let .adapterFailure(message) = error else {
            Issue.record("Expected .adapterFailure, got \(error)"); return
        }
        #expect(message.contains("simulated launch failure"))
    }
}

// MARK: - url.open

@Test("a configured URL opens with its default handler and echoes the resolved target")
func configuredURLOpens() async throws {
    let fake = workspace()
    let result = try await urlCapability(fake).open(urlID: "github")

    #expect(result == URLOpenResult(urlID: "github", opened: true, resolvedURL: "https://github.com"))
    #expect(fake.urlOpens == [URL(string: "https://github.com")])
}

@Test("an unconfigured URL reference is notFound and never reaches the workspace")
func unconfiguredURLIsNotFound() async throws {
    let fake = workspace()
    do {
        _ = try await urlCapability(fake).open(urlID: "intranet")
        Issue.record("Expected notFound for an unconfigured reference")
    } catch let error as NativeCapabilityError {
        guard case let .notFound(message) = error else {
            Issue.record("Expected .notFound, got \(error)"); return
        }
        #expect(message.contains("Settings"))
    }
    #expect(fake.urlOpens.isEmpty)
}

@Test("a malformed configured URL target is adapterFailure, not notFound")
func malformedConfiguredURLIsAdapterFailure() async throws {
    let fake = workspace()
    do {
        _ = try await urlCapability(fake, urls: ["broken": "not a url"]).open(urlID: "broken")
        Issue.record("Expected adapterFailure for a malformed configured target")
    } catch let error as NativeCapabilityError {
        guard case .adapterFailure = error else {
            Issue.record("Expected .adapterFailure, got \(error)"); return
        }
    }
    #expect(fake.urlOpens.isEmpty)
}

// MARK: - url.open re-open surfacing (NIC-145)

/// A fake tab surface returning a fixed outcome and recording the URLs it was
/// asked to surface — so tests can assert whether surfacing was even attempted.
private struct FakeTabSurface: BrowserTabSurface {
    let outcome: BrowserSurfaceOutcome
    let calls: SurfaceCallBox
    func surface(url: URL) async -> BrowserSurfaceOutcome {
        calls.record(url)
        return outcome
    }
}

private final class SurfaceCallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

private let githubURL = URL(string: "https://github.com")!

private func surfacingURLCapability(
    _ fake: FakeWorkspace,
    outcome: BrowserSurfaceOutcome,
    calls: SurfaceCallBox,
    registry: SessionURLOpenRegistry,
    mode: String? = "executive"
) -> NSWorkspaceURLCapability {
    NSWorkspaceURLCapability(
        urlsProvider: { ["github": "https://github.com"] },
        workspace: fake,
        surface: FakeTabSurface(outcome: outcome, calls: calls),
        registry: registry,
        currentModeProvider: { mode }
    )
}

@Test("the first open in a mode opens fresh, records the url, and never consults the surface")
func firstOpenRecordsWithoutSurfacing() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    let calls = SurfaceCallBox()
    let result = try await surfacingURLCapability(fake, outcome: .surfaced, calls: calls, registry: registry)
        .open(urlID: "github")

    #expect(result == URLOpenResult(urlID: "github", opened: true, resolvedURL: "https://github.com", surfaced: false))
    #expect(fake.urlOpens == [githubURL])
    #expect(calls.all.isEmpty) // nothing recorded yet on the first open
    #expect(registry.contains(modeID: "executive", urlID: "github"))
}

@Test("re-opening a recorded url in the same mode surfaces the existing tab, not a new one")
func reopenSurfacesExistingTab() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    registry.record(modeID: "executive", urlID: "github")
    let calls = SurfaceCallBox()
    let result = try await surfacingURLCapability(fake, outcome: .surfaced, calls: calls, registry: registry)
        .open(urlID: "github")

    #expect(result == URLOpenResult(urlID: "github", opened: false, resolvedURL: "https://github.com", surfaced: true))
    #expect(fake.urlOpens.isEmpty) // no duplicate tab opened
    #expect(calls.all == [githubURL])
}

@Test("a recorded url whose tab the user closed falls back to a fresh open")
func closedTabFallsBackToFreshOpen() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    registry.record(modeID: "executive", urlID: "github")
    let calls = SurfaceCallBox()
    let result = try await surfacingURLCapability(fake, outcome: .notFound, calls: calls, registry: registry)
        .open(urlID: "github")

    #expect(result == URLOpenResult(urlID: "github", opened: true, resolvedURL: "https://github.com", surfaced: false))
    #expect(fake.urlOpens == [githubURL])
    #expect(calls.all == [githubURL]) // surfacing was attempted, then fell through
}

@Test("denied automation falls back to a fresh open")
func deniedAutomationFallsBackToFreshOpen() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    registry.record(modeID: "executive", urlID: "github")
    let calls = SurfaceCallBox()
    let result = try await surfacingURLCapability(fake, outcome: .denied, calls: calls, registry: registry)
        .open(urlID: "github")

    #expect(result == URLOpenResult(urlID: "github", opened: true, resolvedURL: "https://github.com", surfaced: false))
    #expect(fake.urlOpens == [githubURL])
}

@Test("a url recorded in another mode is not surfaced in the current mode")
func otherModeRecordIsNotSurfaced() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    registry.record(modeID: "developer", urlID: "github") // recorded elsewhere
    let calls = SurfaceCallBox()
    // Active mode is executive; the developer-mode record must not match.
    let result = try await surfacingURLCapability(fake, outcome: .surfaced, calls: calls, registry: registry, mode: "executive")
        .open(urlID: "github")

    #expect(result.opened)
    #expect(!result.surfaced)
    #expect(fake.urlOpens == [githubURL])
    #expect(calls.all.isEmpty) // surface never consulted for a cross-mode record
}

@Test("with no active mode, surfacing is skipped and nothing is recorded")
func noActiveModeSkipsSurfacing() async throws {
    let fake = workspace()
    let registry = SessionURLOpenRegistry()
    let calls = SurfaceCallBox()
    let result = try await surfacingURLCapability(fake, outcome: .surfaced, calls: calls, registry: registry, mode: nil)
        .open(urlID: "github")

    #expect(result.opened)
    #expect(!result.surfaced)
    #expect(fake.urlOpens == [githubURL])
    #expect(calls.all.isEmpty)
    // No mode to key a record under, so a subsequent open also opens fresh.
    #expect(!registry.contains(modeID: "executive", urlID: "github"))
}

// MARK: - Shared contract suite (FR-TOL-04, MAC-ADAPTER-6 groundwork)

private func nativeBundle(_ fake: FakeWorkspace) -> ToolCapabilities {
    ToolCapabilities(
        app: appCapability(fake),
        url: urlCapability(fake),
        process: MockProcessCapability(matrix: .none),
        systemStatus: MockSystemStatusCapability(matrix: .none),
        nativeCapabilityIDs: [CapabilityMatrix.Capability.appOpen, CapabilityMatrix.Capability.urlOpen]
    )
}

private let nativeFixtures = AdapterContractFixtures(
    appID: "vscode",
    urlID: "github",
    expectedResolvedURL: "https://github.com",
    hookID: "unused",
    hookInvocation: HookInvocation(executable: "/usr/bin/true", arguments: [], workingDirectory: "/", environment: [:]),
    searchQuery: "unused"
)

@Test("the native app/url adapters satisfy the shared capability contract cases (FR-TOL-04)")
func nativeAdaptersSatisfyCapabilityCases() async {
    let cases = AdapterContractSuite.capabilityCases(bundle: nativeBundle(workspace()), fixtures: nativeFixtures)
        .filter { $0.name.hasPrefix("app.open") || $0.name.hasPrefix("url.open") }
    #expect(cases.count == 2)
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}

@Test("the native app/url handlers satisfy the shared handler contract cases (FR-TOL-04)")
func nativeAdaptersSatisfyHandlerCases() async throws {
    let descriptorsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MacAdapterTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory,
        capabilities: nativeBundle(workspace())
    )
    let cases = AdapterContractSuite.handlerCases(registry: registry, fixtures: nativeFixtures)
        .filter { $0.name.hasPrefix("app.open") || $0.name.hasPrefix("url.open") }
    #expect(cases.count == 3)
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}

@Test("the native adapters reproduce the canonical failure kinds through the shared factory (PRD §13.2)")
func nativeAdaptersReproduceCanonicalFailures() async {
    let cases = AdapterContractSuite.failureCases([
        FailureExpectation(name: "unconfigured app reference is notFound", expected: .notFound("x")) {
            _ = try await appCapability(workspace()).open(appID: "photoshop")
        },
        FailureExpectation(name: "missing installed application is notFound", expected: .notFound("x")) {
            _ = try await NSWorkspaceAppCapability(apps: ["vscode": "com.microsoft.VSCode"], workspace: FakeWorkspace()).open(appID: "vscode")
        },
        FailureExpectation(name: "launch failure is adapterFailure", expected: .adapterFailure("x")) {
            _ = try await appCapability(workspace(failsToOpen: true)).open(appID: "vscode")
        },
        FailureExpectation(name: "unconfigured url reference is notFound", expected: .notFound("x")) {
            _ = try await urlCapability(workspace()).open(urlID: "intranet")
        },
    ])
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}
#endif
