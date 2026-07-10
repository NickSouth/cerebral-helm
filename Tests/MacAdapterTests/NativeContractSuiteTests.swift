// NIC-84 (MAC-ADAPTER-6): the shared adapter contract suite against the native
// composition, mock/native equivalence, and proof that native failures cannot
// bypass policy or logging.
//
// NSWorkspace rides its unit-test fake (contract tests never launch real apps);
// hooks run real processes; system status runs the real delta engine over a
// scripted source; the Keychain contract runs in its own opt-in invocation
// (KeychainSecretCapabilityTests — see NIC-123). Gated so the Linux CI package
// build compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralShared
import CerebralTools

// MARK: - The native composition under test

private final class SuiteWorkspace: WorkspaceOpening, @unchecked Sendable {
    struct OpenFailure: Error {}
    let failsToOpen: Bool
    init(failsToOpen: Bool = false) { self.failsToOpen = failsToOpen }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? {
        bundleID == "com.microsoft.VSCode" ? URL(fileURLWithPath: "/Applications/Visual Studio Code.app") : nil
    }
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool { false }
    func openApplication(at url: URL) async throws { if failsToOpen { throw OpenFailure() } }
    func openURL(_ url: URL) async throws { if failsToOpen { throw OpenFailure() } }
}

private final class SuiteMetricSource: SystemMetricSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: Double = 0
    func cpuTicks() -> CPUTicksSample? {
        lock.lock(); defer { lock.unlock() }
        ticks += 400
        return CPUTicksSample(busyTicks: ticks / 4, totalTicks: ticks)
    }
    func memory() -> MemorySample? { MemorySample(usedBytes: 8, totalBytes: 16) }
    func wifiLinkMbps() -> Double? { 866 }
    func battery() -> BatterySample? { BatterySample(percent: 88, isCharging: false, isPluggedIn: true) }
    func displayCount() -> Int? { 2 }
}

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MacAdapterTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private let hookInvocation = HookInvocation(
    executable: "/bin/echo", arguments: ["built"], workingDirectory: "/", environment: ["CI": "true"]
)

private let nativeFixtures = AdapterContractFixtures(
    appID: "vscode",
    urlID: "github",
    expectedResolvedURL: "https://github.com",
    hookID: "echo-hook",
    hookInvocation: hookInvocation,
    expectedHookStdout: "built\n",
    searchQuery: "fixture",
    metrics: [.cpu, .memory]
)

private func nativeBundle(workspace: SuiteWorkspace = SuiteWorkspace()) -> ToolCapabilities {
    ToolCapabilities(
        app: NSWorkspaceAppCapability(apps: ["vscode": "com.microsoft.VSCode"], workspace: workspace),
        url: NSWorkspaceURLCapability(urls: ["github": "https://github.com"], workspace: workspace),
        process: ProcessHookCapability(),
        systemStatus: MacSystemStatusCapability(source: SuiteMetricSource()),
        nativeCapabilityIDs: CapabilityMatrix.Capability.all
    )
}

private func registry(_ bundle: ToolCapabilities) throws -> ToolRegistry {
    try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory(),
        capabilities: bundle,
        knowledge: MockKnowledgeService(hits: [
            NoteSearchHit(
                noteID: "ch-idea-001", title: "Fixture note", excerpt: "Deterministic body.",
                path: "inbox/ch-idea-001.md", updated: "2026-06-23", sensitivity: "private", freshness: "fresh"
            ),
        ]),
        hookCatalog: HookCatalog(["echo-hook": hookInvocation])
    )
}

// MARK: - Full suite against the native composition (FR-TOL-04)

@Test("the native composition satisfies every shared capability and handler contract case")
func nativeCompositionSatisfiesFullSuite() async throws {
    let bundle = nativeBundle()
    let cases = AdapterContractSuite.capabilityCases(bundle: bundle, fixtures: nativeFixtures)
        + AdapterContractSuite.handlerCases(registry: try registry(bundle), fixtures: nativeFixtures)
    #expect(cases.count == 12)
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}

// MARK: - Mock/native equivalence (MAC-ADAPTER-6 AC 1 & 2)

@Test("mock and native compositions produce semantically equivalent executor results, differing only in diagnostics")
func mockNativeEquivalence() async throws {
    // Each scenario runs the SAME invocation through a mock-backed and a
    // native-backed executor. Equivalence is semantic: identical status, error
    // category, and error code. Messages (the diagnostic fields) legitimately
    // differ — that is where platform detail belongs.
    struct Scenario {
        let name: String
        let toolID: String
        let input: String
        let mock: ToolCapabilities
        let native: ToolCapabilities
    }

    let scenarios: [Scenario] = [
        Scenario(
            name: "app.open success",
            toolID: "app.open", input: #"{"appId":"vscode"}"#,
            mock: .mocks(),
            native: nativeBundle()
        ),
        Scenario(
            name: "app.open missing application is a provider failure",
            toolID: "app.open", input: #"{"appId":"vscode"}"#,
            mock: ToolCapabilities(
                app: MockAppCapability(fault: .notFound), url: MockURLCapability(),
                process: MockProcessCapability(), systemStatus: MockSystemStatusCapability()
            ),
            native: ToolCapabilities(
                app: NSWorkspaceAppCapability(apps: ["vscode": "com.missing.App"], workspace: SuiteWorkspace()),
                url: MockURLCapability(), process: MockProcessCapability(),
                systemStatus: MockSystemStatusCapability()
            )
        ),
        Scenario(
            name: "hook.run denied execution",
            toolID: "hook.run", input: #"{"hookId":"echo-hook"}"#,
            mock: ToolCapabilities(
                app: MockAppCapability(), url: MockURLCapability(),
                process: MockProcessCapability(fault: .permissionDenied),
                systemStatus: MockSystemStatusCapability()
            ),
            native: {
                // /etc/hosts exists but is not executable → the native adapter's
                // honest permissionDenied.
                var bundle = nativeBundle()
                return ToolCapabilities(
                    app: bundle.app, url: bundle.url,
                    process: ProcessHookCapability(), systemStatus: bundle.systemStatus
                )
            }()
        ),
    ]

    for scenario in scenarios {
        // The denied-hook native scenario needs a catalog pointing at the
        // non-executable target; every other scenario uses the standard catalog.
        let catalog = scenario.name.contains("denied")
            ? HookCatalog(["echo-hook": HookInvocation(executable: "/etc/hosts", arguments: [], workingDirectory: "/", environment: [:])])
            : HookCatalog(["echo-hook": hookInvocation])

        func execute(_ bundle: ToolCapabilities) async throws -> ToolExecutionResult {
            let registry = try PreMacToolRuntime.makeRegistry(
                descriptorsDirectory: descriptorsDirectory(),
                capabilities: bundle,
                hookCatalog: catalog
            )
            let executor = ToolExecutor(registry: registry, policy: PolicyEngine(), phase: .macOS)
            return await executor.execute(
                ToolInvocation(toolID: scenario.toolID, input: Data(scenario.input.utf8))
            )
        }

        let mockResult = try await execute(scenario.mock)
        let nativeResult = try await execute(scenario.native)

        #expect(mockResult.status == nativeResult.status, Comment(rawValue: scenario.name))
        #expect(mockResult.error?.category == nativeResult.error?.category, Comment(rawValue: scenario.name))
        #expect(mockResult.error?.code == nativeResult.error?.code, Comment(rawValue: scenario.name))
    }
}

// MARK: - Native failures cannot bypass policy or logging (MAC-ADAPTER-6 AC 3)

private func makeNativeRuntime(
    catalog: HookCatalog,
    policy: PolicyEngine = PolicyEngine(),
    toolCallSink: @escaping @Sendable (String, Data) -> Void = { _, _ in }
) throws -> CommandRuntime {
    CommandRuntime(
        registry: try PreMacToolRuntime.makeRegistry(
            descriptorsDirectory: descriptorsDirectory(),
            capabilities: nativeBundle(),
            hookCatalog: catalog
        ),
        policy: policy,
        phase: .macOS,
        coordinator: ConfirmationCoordinator(
            clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0)),
            identifiers: SequentialIdentifierGenerator()
        ),
        factory: CommandFactory(
            clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
            identifiers: SequentialIdentifierGenerator()
        ),
        references: CommandReferences(
            hooks: [ReferenceEntry(id: "touch-hook", label: "Touch Hook", target: "/usr/bin/touch")]
        ),
        hookCatalog: catalog,
        toolCallSink: toolCallSink
    )
}

@Test("a cancelled or policy-denied confirmation never executes the native hook")
func policyGatesNativeExecution() async throws {
    let marker = FileManager.default.temporaryDirectory
        .appendingPathComponent("nic84-policy-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let catalog = HookCatalog([
        "touch-hook": HookInvocation(executable: "/usr/bin/touch", arguments: [marker.path], workingDirectory: "/", environment: [:]),
    ])

    // Cancel: the disclosure appeared, the user declined, the process never ran.
    let runtime = try makeNativeRuntime(catalog: catalog)
    let pending = await runtime.submit("hook touch-hook", source: .cli)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    let cancelled = await runtime.decide(token: token, decision: .cancel)
    guard case let .completed(_, status, _) = cancelled else {
        Issue.record("Expected completed, got \(cancelled)"); return
    }
    #expect(status == .cancelled)
    #expect(!FileManager.default.fileExists(atPath: marker.path), "a cancelled hook must not execute")

    // Deny: policy escalation refuses the class outright — no disclosure, no run.
    let denyAll = PolicyEngine(overrides: PolicyOverrides(minimumDecisions: [.shell: .deny]))
    let denied = await (try makeNativeRuntime(catalog: catalog, policy: denyAll)).submit("hook touch-hook", source: .cli)
    guard case let .completed(_, deniedStatus, deniedResult) = denied else {
        Issue.record("Expected completed, got \(denied)"); return
    }
    #expect(deniedStatus == .failed)
    #expect(deniedResult?.status == .denied)
    #expect(!FileManager.default.fileExists(atPath: marker.path), "a policy-denied hook must not execute")

    // Positive control: the same invocation genuinely executes when approved —
    // proving the negative assertions above tested a live path, not a dead one.
    let approvable = await runtime.submit("hook touch-hook", source: .cli)
    guard case let .awaitingConfirmation(_, _, approveToken) = approvable else {
        Issue.record("Expected awaitingConfirmation, got \(approvable)"); return
    }
    let approved = await runtime.decide(token: approveToken, decision: .approve)
    guard case let .completed(_, approvedStatus, _) = approved else {
        Issue.record("Expected completed, got \(approved)"); return
    }
    #expect(approvedStatus == .succeeded)
    #expect(FileManager.default.fileExists(atPath: marker.path), "an approved hook must actually run")
}

@Test("a native failure is recorded through the tool-call log like any other result")
func nativeFailureIsLogged() async throws {
    let records = RecordCollector()
    let catalog = HookCatalog([
        "touch-hook": HookInvocation(executable: "/does/not/exist", arguments: [], workingDirectory: "/", environment: [:]),
    ])
    let runtime = try makeNativeRuntime(catalog: catalog, toolCallSink: { _, data in records.collect(data) })

    let pending = await runtime.submit("hook touch-hook", source: .cli)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .failed)
    #expect(result?.error?.category == .providerFailure)

    // The failure reached the operational log with the structured error attached.
    let recorded = try #require(records.first)
    let toolResult = try CerebralHelmToolResult(data: recorded)
    #expect(toolResult.toolID == "hook.run")
    #expect(toolResult.status == .failure)
    #expect(toolResult.error != nil)
}

private final class RecordCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [Data] = []
    func collect(_ data: Data) { lock.lock(); records.append(data); lock.unlock() }
    var first: Data? {
        lock.lock(); defer { lock.unlock() }
        return records.first
    }
}
#endif
