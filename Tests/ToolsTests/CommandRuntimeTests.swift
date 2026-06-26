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
    recorder: EventRecorder = EventRecorder()
) throws -> CommandRuntime {
    let hookInvocation = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: ["CI": "true"]
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
        sink: { recorder.record($0) }
    )
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

@Test("a local-write command requires confirmation, then executes on approval (FR-SAF-04)")
func confirmationThenExecution() async throws {
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
    #expect(status == .succeeded)
    #expect(result?.status == .success)
    #expect(recorder.statuses == [.received, .planned, .requiresConfirmation, .running, .succeeded])
}

@Test("a shell hook cannot execute without confirmation, then runs once approved (AC-33.2, FR-SAF-03)")
func shellHookRequiresConfirmation() async throws {
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
    #expect(status == .succeeded)
    #expect(result?.status == .success)
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

@Test("unrecognized input is rejected without executing")
func unrecognizedInputIsRejected() async throws {
    let runtime = try makeRuntime()
    let outcome = await runtime.submit("frobnicate widget", source: .cli)
    guard case .rejected = outcome else {
        Issue.record("Expected rejected, got \(outcome)"); return
    }
}
