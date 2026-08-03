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
    actionPlans: [String: ModePlan] = [:],
    modeStateStore: InMemoryModeStateStore = InMemoryModeStateStore(),
    modeSessionLog: InMemoryModeSessionLog = InMemoryModeSessionLog(),
    toolCallSink: @escaping @Sendable (String, Data) -> Void = { _, _ in },
    actionProgressSink: @escaping @Sendable (WorkflowActionProgress) -> Void = { _ in }
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
        hookCatalog: hookCatalog,
        modeIDs: ["developer"],
        modeStateStore: modeStateStore,
        modeSessionLog: modeSessionLog
    )
    let references = CommandReferences(
        apps: [ReferenceEntry(id: "vscode", label: "VS Code", target: "com.microsoft.VSCode")],
        urls: [ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")],
        hooks: [ReferenceEntry(id: "ondraft-dev", label: "On Draft Dev", target: "/scripts/ondraft.sh")],
        modeIds: ["developer"],
        workflowIds: Array(actionPlans.keys)
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
        modePlanner: StubModePlanner(actionPlans: actionPlans),
        sink: { recorder.record($0) },
        toolCallSink: toolCallSink,
        actionProgressSink: actionProgressSink
    )
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WorkflowActionProgress] = []

    func record(_ progress: WorkflowActionProgress) {
        lock.lock(); storage.append(progress); lock.unlock()
    }

    var all: [WorkflowActionProgress] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
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

@Test("a local-write command runs without confirmation and is refused as phase-unavailable pre-Mac (NIC-111)")
func localWriteRunsThenPhaseUnavailable() async throws {
    // app.open is local_write, which now runs WITHOUT confirmation (only irreversible
    // / external classes gate). It is also Mac-only (availability.preMac == false), so
    // the executor's NIC-111 gate refuses it as unavailable-in-phase: the command
    // terminates `failed` with no confirmation step.
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let outcome = await runtime.submit("open vscode", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed (no confirmation), got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("a project command maps to project.open, runs without confirmation, and is phase-unavailable pre-Mac (NIC-131)")
func projectOpenRunsThenPhaseUnavailable() async throws {
    // `project <path>` parses to the project.open tool (local_write → no confirmation).
    // project.open is Mac-only, so pre-Mac the executor refuses it as unavailable-in-phase —
    // which proves the grammar routes to the project.open tool without gating.
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let outcome = await runtime.submit("project /Users/x/Projects/demo", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed (no confirmation), got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.toolID == "project.open")
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("a google command maps to google.search, runs without confirmation, and is phase-unavailable pre-Mac (NIC-134)")
func googleSearchRunsThenPhaseUnavailable() async throws {
    // `google <query>` parses to the google.search tool (local_write → no confirmation).
    // google.search is Mac-only, so pre-Mac the executor refuses it as unavailable-in-phase —
    // which proves the grammar routes to the google.search tool without gating.
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let outcome = await runtime.submit("google where to watch Dune", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed (no confirmation), got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.toolID == "google.search")
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("a web command maps to web.open, runs without confirmation, and is phase-unavailable pre-Mac (NIC-127)")
func webOpenRunsThenPhaseUnavailable() async throws {
    // `web <url>` parses to the web.open tool (local_write → no confirmation). web.open is
    // Mac-only, so pre-Mac the executor refuses it as unavailable-in-phase — which proves the
    // grammar routes to the web.open tool without gating.
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let outcome = await runtime.submit("web https://news.example.com/story", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed (no confirmation), got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.toolID == "web.open")
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("a user-authored spotify command runs WITHOUT confirmation despite external_write")
func spotifyControlRunsOneClickWhenUserAuthored() async throws {
    // `spotify <action>` parses to spotify.control. Its risk is external_write (honest — it hits
    // Spotify's API), but the descriptor's `allow_external_write_when_user_authored` policy key
    // exempts it for an invocation the user authored, so it must COMPLETE rather than pause for a
    // prompt. spotify.control is Mac-only, so pre-Mac it's phase-unavailable — which together
    // proves the grammar routes to the tool AND the exemption applied (otherwise the outcome
    // would be awaitingConfirmation).
    let recorder = EventRecorder()
    let runtime = try makeRuntime(recorder: recorder)

    let outcome = await runtime.submit("spotify pause", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed (no confirmation — the exemption applied), got \(outcome)"); return
    }
    #expect(status == .failed)
    #expect(result?.toolID == "spotify.control")
    #expect(result?.status == .unavailable)
    #expect(result?.error?.code == "tool.unavailable_in_phase")
    #expect(recorder.statuses == [.received, .planned, .running, .failed])
}

@Test("the SAME spotify command proposed by an agent requires confirmation (provenance tier)")
func spotifyControlConfirmsWhenModelProposed() async throws {
    // Identical input and identical tool as the test above — only the command source differs.
    // The runtime derives provenance from the envelope, so an agent-proposed invocation of a
    // user-exempted tool still pauses for confirmation. This is the end-to-end proof that the
    // exemption is conditioned on WHO authored the arguments, not on which tool was called.
    let runtime = try makeRuntime()

    let outcome = await runtime.submit("spotify pause", source: .agent)
    guard case let .awaitingConfirmation(_, disclosure, _) = outcome else {
        Issue.record("Expected awaitingConfirmation for a model-proposed external write, got \(outcome)"); return
    }
    #expect(disclosure.risk == .externalWrite)
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
    // hook.run (shell) is a gated class, so it pauses for confirmation.
    let pending = await runtime.submit("hook ondraft-dev", source: .cli)
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

@Test("a mode switch runs without confirmation and persists the active mode (NIC-85 re-scope)")
func modeSwitchPersistsWithoutConfirmation() async throws {
    let stateStore = InMemoryModeStateStore()
    let sessionLog = InMemoryModeSessionLog()
    let runtime = try makeRuntime(modeStateStore: stateStore, modeSessionLog: sessionLog)

    // A mode switch runs no workflow steps, so it is a plain local write: no
    // confirmation pause, straight to completion.
    let outcome = await runtime.submit("mode developer", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    #expect(status == .succeeded)
    #expect(result?.status == .success)
    #expect(try stateStore.loadActiveModeID() == "developer")
    #expect(try sessionLog.read().count == 1)
}

// MARK: - Workflow / quick-action execution (NIC-85, FR-MOD-02/03/04)

@Test("a multi-step workflow executes each available step in order and succeeds")
func workflowExecutesEachStep() async throws {
    let recorder = EventRecorder()
    let toolCalls = DataRecorder()
    let runtime = try makeRuntime(
        recorder: recorder,
        actionPlans: ["morning-brief": ModePlan(subjectID: "morning-brief", actions: [
            PlannedAction(actionID: "snapshot", kind: "system.status.read", risk: .readOnly, status: .success, input: Data("{}".utf8)),
            PlannedAction(actionID: "recent-notes", kind: "note.search", risk: .readOnly, status: .success, input: Data(#"{"query":"today"}"#.utf8)),
        ])],
        toolCallSink: { _, data in toolCalls.record(data) }
    )

    let outcome = await runtime.submit("run morning-brief", source: .cli)
    guard case let .completed(_, status, _) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    #expect(status == .succeeded)
    #expect(recorder.statuses == [.received, .planned, .running, .succeeded])
    // Each step is recorded as its own tool call.
    #expect(toolCalls.text.contains("system.status.read"))
    #expect(toolCalls.text.contains("note.search"))
}

@Test("a failed step does not abort the remaining steps (FR-MOD-04)")
func workflowFailedStepContinues() async throws {
    let runtime = try makeRuntime(
        actionPlans: ["brief": ModePlan(subjectID: "brief", actions: [
            // Invalid note.capture input: the handler rejects it, the step fails.
            PlannedAction(actionID: "bad-capture", kind: "note.capture", risk: .localWrite, status: .success, input: Data(#"{"bogus":true}"#.utf8)),
            PlannedAction(actionID: "recent-notes", kind: "note.search", risk: .readOnly, status: .success, input: Data(#"{"query":"today"}"#.utf8)),
        ])]
    )

    let outcome = await runtime.submit("run brief", source: .cli)
    guard case let .completed(_, status, _) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    // The later step still ran and succeeded, so the workflow is a success
    // (partial): the failure is per-action, never a rollback.
    #expect(status == .succeeded)
}

@Test("a workflow containing a hook aggregates to shell and requires one confirmation (FR-MOD-03)")
func workflowWithHookRequiresConfirmation() async throws {
    let runtime = try makeRuntime(
        actionPlans: ["dev-setup": ModePlan(subjectID: "dev-setup", actions: [
            PlannedAction(actionID: "run-hook", kind: "hook.run", risk: .shell, status: .success, input: Data(#"{"hookId":"ondraft-dev"}"#.utf8)),
            PlannedAction(actionID: "recent-notes", kind: "note.search", risk: .readOnly, status: .success, input: Data(#"{"query":"today"}"#.utf8)),
        ])]
    )

    let pending = await runtime.submit("run dev-setup", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, token) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    // One aggregate confirmation for the whole plan, at the strictest step's risk.
    #expect(disclosure.tool.id == "dev-setup")
    #expect(disclosure.risk == .shell)

    let decided = await runtime.decide(token: token, decision: .approve)
    guard case let .completed(_, status, _) = decided else {
        Issue.record("Expected completed, got \(decided)"); return
    }
    // Pre-Mac the hook step terminates unavailable at the executor's availability
    // gate (NIC-111); the search step succeeds, so the workflow ends succeeded.
    #expect(status == .succeeded)
}

@Test("a workflow in which no step succeeds ends failed, never silently succeeded")
func workflowWithNoSuccessesFails() async throws {
    let runtime = try makeRuntime(
        actionPlans: ["mac-only": ModePlan(subjectID: "mac-only", actions: [
            PlannedAction(actionID: "open-editor", kind: "app.open", risk: .localWrite, status: .unavailable, message: "Mac only.", input: Data(#"{"appId":"vscode"}"#.utf8)),
        ])]
    )

    let outcome = await runtime.submit("run mac-only", source: .cli)
    guard case let .completed(_, status, _) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    #expect(status == .failed)
}

@Test("a workflow emits per-action progress: running, terminal, and unavailable steps (FR-CMD-05)")
func workflowEmitsPerActionProgress() async throws {
    let progress = ProgressRecorder()
    let runtime = try makeRuntime(
        actionPlans: ["brief": ModePlan(subjectID: "brief", actions: [
            PlannedAction(actionID: "recent-notes", kind: "note.search", risk: .readOnly, status: .success, input: Data(#"{"query":"today"}"#.utf8)),
            PlannedAction(actionID: "open-editor", kind: "app.open", risk: .localWrite, status: .unavailable, message: "Mac only.", input: Data(#"{"appId":"vscode"}"#.utf8)),
        ])],
        actionProgressSink: { progress.record($0) }
    )

    _ = await runtime.submit("run brief", source: .cli)

    let emitted = progress.all
    // Step 1: started then succeeded. Step 2: planned-unavailable, one event.
    #expect(emitted.map(\.status) == [.running, .succeeded, .unavailable])
    #expect(emitted.map(\.actionID) == ["recent-notes", "recent-notes", "open-editor"])
    #expect(emitted.allSatisfy { $0.workflowID == "brief" && $0.total == 2 })
    #expect(emitted.first?.index == 1)
    #expect(emitted.last?.index == 2)
    #expect(emitted.last?.message == "Mac only.")
    #expect(emitted.allSatisfy { !$0.commandID.isEmpty })
}

@Test("window.arrange runs as a workflow step and reports honest partials (NIC-88)")
func windowArrangeRunsAsWorkflowStep() async throws {
    // The fixture descriptor gates window.arrange to macOS; pre-Mac the step
    // plans unavailable, so this proves both the step shape and the honest gate.
    let toolCalls = DataRecorder()
    let runtime = try makeRuntime(
        actionPlans: ["dev-layout": ModePlan(subjectID: "dev-layout", actions: [
            PlannedAction(
                actionID: "arrange", kind: "window.arrange", risk: .localWrite, status: .unavailable,
                message: "Mac only.",
                input: Data(#"{"arrangement":[{"appId":"vscode","frame":"left-half"}]}"#.utf8)
            ),
            PlannedAction(actionID: "recent-notes", kind: "note.search", risk: .readOnly, status: .success, input: Data(#"{"query":"today"}"#.utf8)),
        ])],
        toolCallSink: { _, data in toolCalls.record(data) }
    )

    let outcome = await runtime.submit("run dev-layout", source: .cli)
    guard case let .completed(_, status, _) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
    }
    // The search step succeeded; the Mac-only arrange step was honestly skipped.
    #expect(status == .succeeded)
    #expect(!toolCalls.text.contains("window.arrange"))
}

@Test("an unknown workflow id is rejected by the parser with suggestions")
func unknownWorkflowRejected() async throws {
    let runtime = try makeRuntime(actionPlans: ["morning-brief": ModePlan(subjectID: "morning-brief", actions: [])])

    let outcome = await runtime.submit("run nope", source: .cli)
    guard case let .rejected(reason, suggestions) = outcome else {
        Issue.record("Expected rejected, got \(outcome)"); return
    }
    #expect(reason.contains("nope"))
    #expect(suggestions == ["morning-brief"])
}

@Test("a secret in a captured note body never reaches the tool-call log (AC-34.1, AC-34.2)")
func capturedNoteSecretIsRedactedEndToEnd() async throws {
    // NIC-111 re-vehicles this end-to-end redaction proof onto note.capture: a
    // pre-Mac-available, redacting tool (descriptor redaction path `/body`). The
    // former hook.run vehicle now terminates `.unavailable` pre-Mac (proven by
    // `hookRunIsRefusedPreMac` below), so it can no longer carry this proof.
    let canary = "CANARY-7f3a9c2e-deploy-token"
    let toolCalls = DataRecorder()
    let runtime = try makeRuntime(toolCallSink: { _, data in toolCalls.record(data) })

    // note.capture is local_write, which runs without confirmation; the canary
    // rides in the note body, which the descriptor marks for redaction.
    let outcome = await runtime.submit("note \(canary)", source: .cli)
    guard case let .completed(_, status, result) = outcome else {
        Issue.record("Expected completed, got \(outcome)"); return
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
        toolCallSink: { _, data in toolCalls.record(data) }
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
