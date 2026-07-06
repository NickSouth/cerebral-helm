// NIC-80 (MAC-ADAPTER-2): allowlisted hook process adapter.
//
// These tests run real processes (/bin/echo, /bin/sh, /bin/sleep) — cheap,
// deterministic system binaries — because the adapter's contract is precisely
// its real process behavior: exact invocation, bounded environment, output
// caps, and group kill with no surviving child. Gated so the Linux CI package
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

private func invocation(
    _ executable: String,
    _ arguments: [String] = [],
    workingDirectory: String = "/",
    environment: [String: String] = [:]
) -> HookInvocation {
    HookInvocation(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment
    )
}

/// A unique-per-call marker a sleeping grandchild carries in its argv, so tests
/// can find survivors with pgrep without knowing pids. Tests run concurrently in
/// one process, so the pid alone is NOT unique enough — a shared marker lets one
/// test's sleeper appear as another's survivor.
private let markerCounter = NSLock()
private nonisolated(unsafe) var markerSequence = 0
private func sleepMarker() -> String {
    markerCounter.lock()
    markerSequence += 1
    let sequence = markerSequence
    markerCounter.unlock()
    return "30.\(sequence)\(ProcessInfo.processInfo.processIdentifier % 10000)"
}

private func survivorCount(matching marker: String) -> Int {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", "sleep \(marker)"]
    let out = Pipe()
    pgrep.standardOutput = out
    try? pgrep.run()
    pgrep.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? 0 : text.split(separator: "\n").count
}

private func waitUntil(_ deadlineMs: Int, _ condition: () -> Bool) async {
    let steps = max(1, deadlineMs / 50)
    for _ in 0..<steps {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

// MARK: - Execution shape

@Test("a hook runs the exact invocation and captures exit code, stdout, and duration")
func exactInvocationRuns() async throws {
    let result = try await ProcessHookCapability().run(invocation("/bin/echo", ["built"], environment: ["CI": "true"]))

    #expect(result.exitCode == 0)
    #expect(result.stdout == "built\n")
    #expect(result.stderr.isEmpty)
    #expect(result.environment == ["CI": "true"])
    #expect(!result.timedOut)
    #expect(result.durationMs >= 0)
}

@Test("a nonzero exit code and stderr are reported, not masked")
func nonzeroExitAndStderr() async throws {
    let result = try await ProcessHookCapability().run(
        invocation("/bin/sh", ["-c", "echo broken 1>&2; exit 3"])
    )

    #expect(result.exitCode == 3)
    #expect(result.stderr == "broken\n")
}

@Test("the child environment is exactly the configured environment — nothing inherited (FR-TOL-05)")
func environmentIsBounded() async throws {
    // /usr/bin/env prints the environ verbatim: exactly the one configured
    // variable, none of the parent app's environment. (A shell would be a bad
    // probe here — sh synthesizes a default PATH when none is set.)
    let result = try await ProcessHookCapability().run(
        invocation("/usr/bin/env", environment: ["HOOK_MARKER": "m1"])
    )

    #expect(result.stdout == "HOOK_MARKER=m1\n")
}

@Test("a relative configured executable resolves against the working directory, never PATH")
func relativeExecutableResolvesAgainstWorkingDirectory() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("hook-adapter-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("hook.sh")
    try "#!/bin/sh\necho from-script\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let result = try await ProcessHookCapability().run(
        invocation("hook.sh", workingDirectory: directory.path)
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout == "from-script\n")
}

@Test("output beyond the limit is truncated with an explicit marker, and the hook still completes")
func outputIsCapped() async throws {
    let capability = ProcessHookCapability(outputLimitBytes: 64)
    let result = try await capability.run(
        invocation("/bin/sh", ["-c", "printf '%02000d' 0"])
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("…[output truncated]"))
    // 64 bytes kept + marker; the other ~1936 bytes were drained, not stored.
    #expect(result.stdout.count < 100)
}

// MARK: - Failure kinds

@Test("missing and non-executable hook targets map to the canonical failure kinds")
func missingAndDeniedExecutables() async throws {
    let cases = AdapterContractSuite.failureCases([
        FailureExpectation(name: "missing hook executable is notFound", expected: .notFound("x")) {
            _ = try await ProcessHookCapability().run(invocation("/does/not/exist"))
        },
        FailureExpectation(name: "non-executable hook target is permissionDenied", expected: .permissionDenied) {
            _ = try await ProcessHookCapability().run(invocation("/etc/hosts"))
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

// MARK: - Cancellation and timeout cleanup (the NIC-80 core AC)

@Test("cancellation kills the whole process group — the grandchild does not survive")
func cancellationKillsProcessGroup() async throws {
    let marker = sleepMarker()
    // /bin/sh forks /bin/sleep as a grandchild (same process group). Killing
    // only the direct child would orphan the sleep.
    let running = Task {
        try await ProcessHookCapability().run(
            invocation("/bin/sh", ["-c", "/bin/sleep \(marker) & wait"])
        )
    }
    await waitUntil(3000) { survivorCount(matching: marker) > 0 }
    #expect(survivorCount(matching: marker) > 0, "the grandchild sleeper should be running before cancellation")

    running.cancel()
    let outcome = await running.result
    guard case let .failure(error) = outcome, error is CancellationError else {
        Issue.record("Expected CancellationError, got \(outcome)"); return
    }

    await waitUntil(2000) { survivorCount(matching: marker) == 0 }
    #expect(survivorCount(matching: marker) == 0, "no unmanaged child may survive cancellation")
}

@Test("an executor timeout kills the process group and reports .timeout (AC-29.2, NIC-80)")
func executorTimeoutLeavesNoChild() async throws {
    let marker = sleepMarker()
    let descriptors = try ToolDescriptorCatalog.loadDescriptors(
        directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MacAdapterTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    )
    let hookDescriptor = try #require(descriptors.first { $0.id == "hook.run" })
    let catalog = HookCatalog([
        "slow-hook": invocation("/bin/sh", ["-c", "/bin/sleep \(marker) & wait"]),
    ])
    var builder = ToolRegistryBuilder()
    try builder.register(
        descriptor: hookDescriptor,
        handler: HookRunHandler(catalog: catalog, capability: ProcessHookCapability()),
        overlay: ConfiguredTool(id: "hook.run", risk: "shell", timeoutMs: 300, availableInPreMac: false)
    )
    let executor = ToolExecutor(registry: builder.build(), policy: PolicyEngine(), phase: .macOS)

    let result = await executor.execute(
        ToolInvocation(toolID: "hook.run", input: Data(#"{"hookId":"slow-hook"}"#.utf8))
    )

    #expect(result.status == .timeout)
    await waitUntil(2000) { survivorCount(matching: marker) == 0 }
    #expect(survivorCount(matching: marker) == 0, "an executor timeout may not leave an unmanaged child")
}

// MARK: - Confirmation preview matches execution (FR-SAF-03)

@Test("the confirmed hook executes the exact catalog invocation the disclosure was built from")
func confirmationPreviewMatchesExecution() async throws {
    // The disclosure and the handler resolve through the SAME HookCatalog entry;
    // approving the disclosed command runs exactly that invocation — proven by
    // the process's observable output.
    let descriptors = try ToolDescriptorCatalog.loadDescriptors(
        directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    )
    let hookInvocation = invocation("/bin/echo", ["exact-disclosed-invocation"], environment: ["CI": "true"])
    let catalog = HookCatalog(["ondraft-dev": hookInvocation])
    var builder = ToolRegistryBuilder()
    for descriptor in descriptors {
        if descriptor.id == "hook.run" {
            try builder.register(
                descriptor: descriptor,
                handler: HookRunHandler(catalog: catalog, capability: ProcessHookCapability())
            )
        }
    }
    let runtime = CommandRuntime(
        registry: builder.build(),
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
            hooks: [ReferenceEntry(id: "ondraft-dev", label: "On Draft Dev", target: "/bin/echo")]
        ),
        hookCatalog: catalog
    )

    let pending = await runtime.submit("hook ondraft-dev", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    #expect(disclosure.risk == .shell)
    #expect(disclosure.tool.id == "hook.run")

    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .succeeded)
    #expect(result?.status == .success)
    let output = try CerebralHelmHookRunOutput(data: try #require(result?.output))
    #expect(output.stdout == "exact-disclosed-invocation\n")
    #expect(output.environment == ["CI": "true"])
}

// MARK: - Shared contract suite

@Test("the native process adapter satisfies the shared process contract case (FR-TOL-04)")
func nativeProcessAdapterSatisfiesContractCase() async {
    let fixtures = AdapterContractFixtures(
        appID: "unused",
        urlID: "unused",
        hookID: "echo-hook",
        hookInvocation: invocation("/bin/echo", ["built"], environment: ["CI": "true"]),
        expectedHookStdout: "built\n",
        searchQuery: "unused"
    )
    let bundle = ToolCapabilities(
        app: MockAppCapability(),
        url: MockURLCapability(),
        process: ProcessHookCapability(),
        systemStatus: MockSystemStatusCapability(),
        nativeCapabilityIDs: [CapabilityMatrix.Capability.hookRun]
    )
    let cases = AdapterContractSuite.capabilityCases(bundle: bundle, fixtures: fixtures)
        .filter { $0.name.hasPrefix("process") }
    #expect(cases.count == 1)
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch {
            Issue.record("[\(contractCase.name)] \(error)")
        }
    }
}
#endif
