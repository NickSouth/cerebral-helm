import Foundation
import Testing

import CerebralContracts
import CerebralCore

/// NIC-29 (PRE-SAFETY-2): tool executor with timeout and cancellation.
///
/// AC-29.1 denied calls never reach handlers; AC-29.2 timeout and cancellation
/// are distinguishable; AC-29.3 long calls do not block other work.

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private func descriptor(_ id: String) throws -> CerebralHelmToolDescriptor {
    try #require(try ToolDescriptorCatalog.loadDescriptors(directory: descriptorsDirectory()).first { $0.id == id })
}

private func executor(
    for id: String,
    handler: any ToolHandler,
    overlay: ConfiguredTool? = nil,
    policy: PolicyEngine = PolicyEngine(),
    phase: ExecutionPhase = .preMac
) throws -> ToolExecutor {
    var builder = ToolRegistryBuilder()
    try builder.register(descriptor: try descriptor(id), handler: handler, overlay: overlay)
    return ToolExecutor(registry: builder.build(), policy: policy, phase: phase)
}

private func invocation(_ id: String) -> ToolInvocation {
    ToolInvocation(toolID: id, input: Data("{}".utf8))
}

// MARK: - Test handlers

private struct EchoHandler: ToolHandler {
    let toolID: String
    func execute(input: Data) async throws -> Data { input }
}

private struct SleepingHandler: ToolHandler {
    let toolID: String
    let sleepMs: Int
    func execute(input: Data) async throws -> Data {
        try await Task.sleep(nanoseconds: UInt64(sleepMs) * 1_000_000)
        return input
    }
}

private struct FailingHandler: ToolHandler {
    let toolID: String
    let error: ToolHandlerError
    func execute(input: Data) async throws -> Data { throw error }
}

private actor SpyHandler: ToolHandler {
    nonisolated let toolID: String
    private(set) var invoked = false

    init(toolID: String) { self.toolID = toolID }

    func execute(input: Data) async throws -> Data {
        invoked = true
        return input
    }
}

// MARK: - Tests

@Test("a denied call never reaches the handler (AC-29.1)")
func deniedCallNeverReachesHandler() async throws {
    let spy = SpyHandler(toolID: "system.status.read")
    // Force a deny by escalating the tool's read_only class to deny.
    let denyAll = PolicyEngine(overrides: PolicyOverrides(minimumDecisions: [.readOnly: .deny]))
    let executor = try executor(for: "system.status.read", handler: spy, policy: denyAll)

    let result = await executor.execute(invocation("system.status.read"))

    #expect(result.status == .denied)
    #expect(result.error?.category == .policyDenied)
    #expect(await spy.invoked == false)
}

@Test("an allowed call runs the handler and returns its output")
func allowedCallSucceeds() async throws {
    let executor = try executor(for: "system.status.read", handler: EchoHandler(toolID: "system.status.read"))
    let result = await executor.execute(ToolInvocation(toolID: "system.status.read", input: Data(#"{"ok":true}"#.utf8)))

    #expect(result.status == .success)
    #expect(result.output == Data(#"{"ok":true}"#.utf8))
    #expect(result.error == nil)
}

@Test("a handler that exceeds its timeout yields a timeout result (AC-29.2)")
func timeoutIsDistinct() async throws {
    // A stricter overlay shortens the timeout to 50ms; the handler sleeps far longer.
    let overlay = ConfiguredTool(id: "system.status.read", risk: "read_only", timeoutMs: 50, availableInPreMac: true)
    let executor = try executor(
        for: "system.status.read",
        handler: SleepingHandler(toolID: "system.status.read", sleepMs: 5000),
        overlay: overlay
    )

    let result = await executor.execute(invocation("system.status.read"))

    #expect(result.status == .timeout)
    #expect(result.error?.category == .timeout)
}

@Test("an externally cancelled call yields a cancelled result, distinct from timeout (AC-29.2)")
func cancellationIsDistinct() async throws {
    // Long timeout so the deadline never fires; cancellation must win.
    let executor = try executor(
        for: "system.status.read",
        handler: SleepingHandler(toolID: "system.status.read", sleepMs: 5000)
    )

    let task = Task { await executor.execute(invocation("system.status.read")) }
    try await Task.sleep(nanoseconds: 30_000_000) // let it enter the handler
    task.cancel()
    let result = await task.value

    #expect(result.status == .cancelled)
    #expect(result.error?.category == .cancelled)
}

@Test("a long call does not block a concurrent fast call (AC-29.3)")
func longCallDoesNotBlockOthers() async throws {
    let slow = try executor(for: "system.status.read", handler: SleepingHandler(toolID: "system.status.read", sleepMs: 400))
    let fast = try executor(for: "note.search", handler: EchoHandler(toolID: "note.search"))

    async let slowResult = slow.execute(invocation("system.status.read"))
    async let fastResult = fast.execute(invocation("note.search"))

    // The fast call completes and is observable without awaiting the slow one.
    let fastDone = await fastResult
    #expect(fastDone.status == .success)

    let slowDone = await slowResult
    #expect(slowDone.status == .success)
}

@Test("handler errors map to stable categories (FR-TOL-06)")
func handlerErrorsMapToCategories() async throws {
    let cases: [(ToolHandlerError, ToolResultStatus, CerebralContracts.Category)] = [
        (.invalidInput("bad"), .failure, .invalidInput),
        (.unavailable("no adapter"), .unavailable, .unavailableCapability),
        (.permissionDenied("nope"), .denied, .permissionDenied),
        (.providerFailure("boom"), .failure, .providerFailure),
    ]

    for (error, expectedStatus, expectedCategory) in cases {
        let executor = try executor(for: "note.search", handler: FailingHandler(toolID: "note.search", error: error))
        let result = await executor.execute(invocation("note.search"))
        #expect(result.status == expectedStatus, "\(error)")
        #expect(result.error?.category == expectedCategory, "\(error)")
    }
}

@Test("an unknown tool resolves to an unavailable result without a handler")
func unknownToolIsUnavailable() async throws {
    let executor = try executor(for: "note.search", handler: EchoHandler(toolID: "note.search"))
    let result = await executor.execute(invocation("does.not.exist"))

    #expect(result.status == .unavailable)
    #expect(result.error?.category == .unavailableCapability)
}

@Test("a tool unavailable in the current phase is refused without reaching its handler (NIC-111)")
func phaseUnavailableToolIsRefused() async throws {
    // hook.run declares availability.preMac == false, so the registry computes
    // availableInPreMac == false. The executor must refuse it before the handler
    // runs — distinct from `tool.unknown` (the tool is registered and bound).
    let spy = SpyHandler(toolID: "hook.run")
    let executor = try executor(for: "hook.run", handler: spy)

    let result = await executor.execute(invocation("hook.run"))

    #expect(result.status == .unavailable)
    #expect(result.error?.category == .unavailableCapability)
    #expect(result.error?.code == "tool.unavailable_in_phase")
    // The handler is never invoked: a phase-unavailable tool cannot execute.
    #expect(await spy.invoked == false)
}

@Test("a Mac-only tool executes when the runtime is composed for the macOS phase")
func macOnlyToolRunsInMacPhase() async throws {
    // hook.run declares availability.preMac == false but availability.macOS ==
    // true. The same registration that is refused pre-Mac must pass the gate in
    // a `.macOS`-phase executor and reach its handler.
    let spy = SpyHandler(toolID: "hook.run")
    let executor = try executor(for: "hook.run", handler: spy, phase: .macOS)

    let result = await executor.execute(invocation("hook.run"))

    #expect(result.status == .success)
    #expect(await spy.invoked == true)
}

@Test("a tool the descriptor marks unavailable on macOS is refused in the macOS phase")
func macUnavailableToolIsRefusedInMacPhase() async throws {
    // No shipped tool is preMac-only, so construct one: note.search with its
    // macOS availability turned off. The gate must read the phase-matching flag,
    // not the pre-Mac one.
    let preMacOnly = try descriptor("note.search").with(availability: AvailabilityClass(macOS: false, preMAC: true))
    let spy = SpyHandler(toolID: "note.search")
    var builder = ToolRegistryBuilder()
    try builder.register(descriptor: preMacOnly, handler: spy)
    let executor = ToolExecutor(registry: builder.build(), policy: PolicyEngine(), phase: .macOS)

    let result = await executor.execute(invocation("note.search"))

    #expect(result.status == .unavailable)
    #expect(result.error?.code == "tool.unavailable_in_phase")
    #expect(await spy.invoked == false)
}
