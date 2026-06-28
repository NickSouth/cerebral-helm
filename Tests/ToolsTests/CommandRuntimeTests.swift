import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared
import CerebralTools

/// Wiring: the live command path (`CommandRuntime`) ties the parser, registry,
/// policy, confirmation coordinator, executor, and handlers into one flow.

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ToolsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CommandStatus] = []

    func record(_ event: CommandLifecycleEvent) {
        lock.lock(); storage.append(event.currentStatus); lock.unlock()
    }

    var statuses: [CommandStatus] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private func makeRuntime(
    knowledge: any KnowledgeService = MockKnowledgeService(),
    policy: PolicyEngine = PolicyEngine(),
    recorder: EventRecorder = EventRecorder(),
    hookEnvironment: [String: String] = ["CI": "true"],
    toolCallSink: @escaping @Sendable (Data) -> Void = { _ in }
) throws -> CommandRuntime {
    let hookInvocation = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: hookEnvironment
    )
    let hookCatalog = HookCatalog(["ondraft-dev": hookInvocation])
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory(),
        knowledge: knowledge,
        hookCatalog: hookCatalog
    )
    let references = CommandReferences(
        apps: [ReferenceEntry(id: "vscode", label: "VS Code", target: "com.microsoft.VSCode")],
        urls: [ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")],
        hooks: [ReferenceEntry(id: "ondraft-dev", label: "On Draft Dev", target: "/scripts/ondraft.sh")],
        modeIds: ["developer"]
    )
    let factory = CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
    let coordinator = ConfirmationCoordinator(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0)),
        identifiers: SequentialIdentifierGenerator()
    )
    return CommandRuntime(
        registry: registry,
        policy: policy,
        coordinator: coordinator,
        factory: factory,
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: StubModePlanner(),
        sink: { recorder.record($0) },
        toolCallSink: toolCallSink
    )
}

private final class DataRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [Data] = []

    func record(_ data: Data) {
        lock.lock(); lines.append(data); lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
    }
}

@Test("an allowed read-only command executes end to end through the wired stack")
func allowedCommandExecutes() async throws {
    let recorder = EventRecorder()
    let knowledge = MockKnowledgeService(hits: [
        NoteSearchHit(noteID: "ch-idea-001", title: "n", excerpt: "e", path: "p.md", updated: "2026-06-23", sensitivity: nil, freshness: nil),
    ])
    let runtime = try makeRuntime(knowledge: knowledge, recorder: recorder)

    let outcome = await runtime.submit("search updater", source: .cli)

    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    #expect(status == .succeeded)
    #expect(result?.status == .success)
    #expect(recorder.statuses == [.received, .planned, .running, .succeeded])
}

@Test("a local-write command requires confirmation, then is refused as phase-unavailable on approval (FR-SAF-04, NIC-111)")
func confirmationThenExecution() async throws {
    // app.open declares availability.preMac == false. The confirmation path is
    // unchanged — it still pauses and discloses a local_write action — but on
    // approval the executor's NIC-111 availability gate refuses it: the command
    // terminates `failed` with an `.unavailable` result, never running the
    // handler. (A pre-Mac-available local_write tool — note.capture — is exercised
    // end-to-end in `capturedNoteSecretIsRedactedEndToEnd`.)
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let pending = await runtime.submit("open vscode", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    #expect(disclosure.tool.id == "app.open")
    #expect(disclosure.risk == .localWrite)
    #expect(disclosure.choices.defaultFocusedChoice == .review)

    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .failed)
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .requiresConfirmation, .running, .failed])
}

@Test("a shell hook requires confirmation, then is refused as phase-unavailable on approval (AC-33.2, FR-SAF-03, NIC-111)")
func shellHookRequiresConfirmation() async throws {
    // hook.run declares availability.preMac == false. Confirmation still gates the
    // shell class, but approval no longer runs it: the NIC-111 availability gate
    // returns `.unavailable` and the command terminates `failed`, so the
    // shell-class handler never executes pre-Mac.
    let runtime = try makeRuntime()

    let pending = await runtime.submit("hook ondraft-dev", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    #expect(disclosure.risk == .shell)

    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .failed)
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
}

@Test("a replayed approval is refused (AC-31.1, wired)")
func replayedApprovalRefused() async throws {
    let runtime = try makeRuntime()
    let pending = await runtime.submit("open vscode", source: .cli)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("Expected awaitingConfirmation"); return
    }

    _ = await runtime.decide(token: token, decision: .approve)
    let replay = await runtime.decide(token: token, decision: .approve)

    guard case let .rejected(reason, _) = replay else {
        Issue.record("Expected rejected, got \(replay)"); return
    }
    #expect(reason.contains("alreadyUsed"))
}

@Test("a denied command ends failed without invoking the handler (AC-29.1)")
func deniedCommandNeverExecutes() async throws {
    let recorder = EventRecorder()
    let runtime = try makeRuntime(
        policy: PolicyEngine(overrides: PolicyOverrides(minimumDecisions: [.readOnly: .deny])),
        recorder: recorder
    )

    let outcome = await runtime.submit("search updater", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.status == .denied)
    #expect(result?.error?.category == .policyDenied)
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("a mode whose plan contains a hook aggregates to shell and requires confirmation (FR-MOD-03)")
func modeWithHookAggregatesToShell() async throws {
    let runtime = try makeRuntime()

    let pending = await runtime.submit("mode developer", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    // The disclosure shows the aggregate risk, not the declared local_write.
    #expect(disclosure.tool.id == "mode.apply")
    #expect(disclosure.risk == .shell)

    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .succeeded)
    #expect(result?.status == .success)
}

@Test("a secret in a captured note body never reaches the tool-call log (AC-34.1, AC-34.2)")
func capturedNoteSecretIsRedactedEndToEnd() async throws {
    // NIC-111 re-vehicles this end-to-end redaction proof onto note.capture: a
    // pre-Mac-available, redacting tool (descriptor redaction path `/body`). The
    // former hook.run vehicle now terminates `.unavailable` pre-Mac (proven by
    // `hookRunIsRefusedPreMac` below), so it can no longer carry this proof.
    let canary = "CANARY-7f3a9c2e-deploy-token"
    let toolCalls = DataRecorder()
    let runtime = try makeRuntime(toolCallSink: { toolCalls.record($0) })

    // note.capture is local_write, so it pauses for confirmation; the canary
    // rides in the note body, which the descriptor marks for redaction.
    let pending = await runtime.submit("note \(canary)", source: .cli)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    #expect(status == .succeeded)
    #expect(result?.status == .success)

    let recorded = toolCalls.text
    #expect(!recorded.isEmpty)
    #expect(!recorded.contains(canary))         // AC-34.1: the secret never reaches the log
    #expect(recorded.contains("note.capture"))  // AC-34.2: useful context preserved
    #expect(recorded.contains(SchemaRedactor.marker))
}

@Test("the pre-Mac-unavailable hook.run shell tool is refused even after approval (NIC-111)")
func hookRunIsRefusedPreMac() async throws {
    // hook.run declares availability.preMac == false. Even when the caller
    // approves the shell confirmation, the executor's availability gate refuses
    // it: the result is `.unavailable` with the distinct phase code, and the
    // command terminates `failed` (no shell handler runs pre-Mac).
    let canary = "CANARY-7f3a9c2e-deploy-token"
    let toolCalls = DataRecorder()
    let runtime = try makeRuntime(
        hookEnvironment: ["DEPLOY_TOKEN": canary],
        toolCallSink: { toolCalls.record($0) }
    )

    let pending = await runtime.submit("hook ondraft-dev", source: .cli)
    guard case let .awaitingConfirmation(_, _, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, result) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    // The shell tool never ran: it is refused as unavailable in this phase.
    #expect(status == .failed)
    #expect(result?.status == .unavailable)
    #expect(result?.error?.category == .unavailableCapability)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    // And the secret-bearing environment is still kept out of the log.
    #expect(!toolCalls.text.contains(canary))
}

@Test("unrecognized input is rejected without executing")
func unrecognizedInputIsRejected() async throws {
    let runtime = try makeRuntime()
    let outcome = await runtime.submit("frobnicate widget", source: .cli)
    guard case .rejected = outcome else {
        Issue.record("Expected rejected, got \(outcome)"); return
    }
}
