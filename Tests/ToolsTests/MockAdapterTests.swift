import Testing

import CerebralAdapterContractSuite
import CerebralCore
import CerebralTools

/// NIC-32 (PRE-SAFETY-5): mock native adapters and capability matrix.
///
/// AC-32.1 every native protocol has a mock; AC-32.2 capability flags drive
/// unavailable states; AC-32.3 mocks reproduce canonical failure fixtures. The
/// canonical-failure and result-shape checks run through the shared contract
/// suite so the native adapters satisfy the identical cases (MAC-ADAPTER-6).

private func invocation() -> HookInvocation {
    HookInvocation(executable: "/usr/bin/just", arguments: ["build"], workingDirectory: "/repo", environment: ["CI": "true"])
}

@Test("every native capability protocol has a working mock (AC-32.1)")
func everyCapabilityHasAMock() async throws {
    let app = try await MockAppCapability().open(appID: "vscode")
    #expect(app == AppOpenResult(appID: "vscode", launched: true, alreadyRunning: false))

    let url = try await MockURLCapability(resolvedURLs: ["github": "https://github.com"]).open(urlID: "github")
    #expect(url.opened)
    #expect(url.resolvedURL == "https://github.com")

    let process = try await MockProcessCapability(stdout: "ok").run(invocation())
    #expect(process.exitCode == 0)
    #expect(process.stdout == "ok")
    #expect(process.environment == ["CI": "true"])
    #expect(!process.timedOut)

    let metrics = try await MockSystemStatusCapability().readMetrics([.cpu, .memory])
    #expect(metrics.count == 2)
    #expect(metrics.allSatisfy { $0.availability == .available })

    let secret = try await MockSecretCapability(resolvableReferences: ["openai_api_key"]).resolve(reference: "openai_api_key")
    #expect(secret.isResolved)
    #expect(secret.reference == "openai_api_key")

    let windows = try await MockWindowCapability(windows: [WindowInfo(id: "w1", title: "Editor", isFocused: true)]).inspect()
    #expect(windows.count == 1)
}

@Test("a disabled capability flag drives an unavailable state (AC-32.2)")
func capabilityFlagsDriveUnavailable() async throws {
    let off = CapabilityMatrix.none

    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockAppCapability(matrix: off).open(appID: "vscode") }
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockURLCapability(matrix: off).open(urlID: "github") }
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockProcessCapability(matrix: off).run(invocation()) }
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockSystemStatusCapability(matrix: off).readMetrics([.cpu]) }
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockSecretCapability(matrix: off).resolve(reference: "k") }
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockWindowCapability(matrix: off).inspect() }

    // A selectively-enabled matrix gates only the named capability.
    let onlyApp = CapabilityMatrix(available: [CapabilityMatrix.Capability.appOpen])
    let launched = try await MockAppCapability(matrix: onlyApp).open(appID: "vscode")
    #expect(launched.launched)
    await #expect(throws: NativeCapabilityError.unavailable) { _ = try await MockURLCapability(matrix: onlyApp).open(urlID: "github") }
}

@Test("the mock bundle satisfies the shared capability contract cases (FR-TOL-04)")
func mockBundleSatisfiesCapabilityCases() async {
    let cases = AdapterContractSuite.capabilityCases(
        bundle: MockContractComposition.bundle(),
        fixtures: MockContractComposition.fixtures
    )
    #expect(cases.count == 4)
    await runContractCases(cases)
}

@Test("mocks reproduce canonical native failure fixtures (AC-32.3)")
func canonicalFailures() async throws {
    // The expectations run through the shared failure-case factory: the mock
    // provokes each kind by fault injection; the native adapters provoke the
    // same kinds with genuinely failing inputs (MAC-ADAPTER-6).
    let cases = AdapterContractSuite.failureCases([
        FailureExpectation(name: "missing configured application is notFound", expected: .notFound("safari")) {
            _ = try await MockAppCapability(fault: .notFound).open(appID: "safari")
        },
        FailureExpectation(name: "denied process execution is permissionDenied", expected: .permissionDenied) {
            _ = try await MockProcessCapability(fault: .permissionDenied).run(invocation())
        },
        FailureExpectation(name: "exceeded deadline is timedOut", expected: .timedOut) {
            _ = try await MockProcessCapability(fault: .timeout).run(invocation())
        },
        FailureExpectation(name: "cancellation during execution is cancelled", expected: .cancelled) {
            _ = try await MockProcessCapability(fault: .cancelled).run(invocation())
        },
        FailureExpectation(name: "generic adapter failure is adapterFailure", expected: .adapterFailure("boom")) {
            _ = try await MockAppCapability(fault: .adapterFailure("boom")).open(appID: "x")
        },
        FailureExpectation(name: "absent capability is unavailable", expected: .unavailable) {
            _ = try await MockAppCapability(matrix: .none).open(appID: "vscode")
        },
    ])
    await runContractCases(cases)
}

@Test("the suite reports a violation when an expected failure unexpectedly succeeds")
func suiteDetectsViolations() async throws {
    // Self-check of the shared mechanism: a contract case must throw a
    // violation, not pass silently, when reality diverges from the expectation.
    let cases = AdapterContractSuite.failureCases([
        FailureExpectation(name: "expected-to-fail", expected: .notFound("x")) {
            _ = try await MockAppCapability().open(appID: "vscode") // succeeds
        },
    ])
    await #expect(throws: AdapterContractViolation.self) {
        try await cases[0].run()
    }
}

@Test("system metrics expose per-metric availability states (AC-32.2, AC-32.3)")
func perMetricAvailability() async throws {
    let mock = MockSystemStatusCapability(
        perMetricAvailability: [
            .cpu: .available,
            .memory: .stale,
            .network: .disconnected,
            .battery: .unavailable,
            .display: .loading,
        ],
        values: [.cpu: 12.5]
    )
    let readings = try await mock.readMetrics(SystemMetricID.allCases)
    let byID = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })

    #expect(byID[.cpu]?.availability == .available)
    #expect(byID[.cpu]?.value == 12.5)
    #expect(byID[.memory]?.availability == .stale)
    #expect(byID[.network]?.availability == .disconnected)
    #expect(byID[.battery]?.availability == .unavailable)
    #expect(byID[.display]?.availability == .loading)
    // A metric that is not available carries no value.
    #expect(byID[.battery]?.value == nil)
}
