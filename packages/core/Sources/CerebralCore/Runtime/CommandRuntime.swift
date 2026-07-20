import Foundation
import CerebralContracts
import CerebralShared

/// One step's live progress while a workflow / quick action executes
/// (FR-CMD-05): emitted when the step starts and again at its terminal status,
/// so the dashboard can render per-action progress without parsing log strings.
public struct WorkflowActionProgress: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case running
        case succeeded
        case failed
        case unavailable
        case cancelled
    }

    public let commandID: String
    public let workflowID: String
    public let actionID: String
    /// The step's tool id.
    public let kind: String
    public let status: Status
    /// 1-based position of this step in the plan.
    public let index: Int
    public let total: Int
    public let message: String?

    public init(
        commandID: String, workflowID: String, actionID: String, kind: String,
        status: Status, index: Int, total: Int, message: String? = nil
    ) {
        self.commandID = commandID
        self.workflowID = workflowID
        self.actionID = actionID
        self.kind = kind
        self.status = status
        self.index = index
        self.total = total
        self.message = message
    }
}

/// The result of submitting or deciding a command on the runtime.
public enum CommandRuntimeOutcome {
    /// The command reached a terminal status. `result` carries the tool's
    /// structured result when execution ran.
    case completed(commandID: String, status: CommandStatus, result: ToolExecutionResult?)
    /// The command is paused for confirmation. Present the disclosure and call
    /// ``CommandRuntime/decide(token:decision:)`` with the token.
    case awaitingConfirmation(commandID: String, disclosure: CerebralHelmConfirmationDisclosure, token: ConfirmationToken)
    /// The input did not resolve to a command and nothing executed.
    case rejected(reason: String, suggestions: [String])
}

/// The application-level command path: it parses input, maps the intent to a
/// validated tool, evaluates policy, gates on confirmation, executes through the
/// tool executor, and emits lifecycle events — wiring together the registry
/// (NIC-28), policy (NIC-30), executor (NIC-29), confirmation (NIC-31), and
/// handlers (NIC-33). The synchronous ``CommandBus`` remains the lifecycle and
/// subscription primitive; this is the async execution authority for tools.
public final class CommandRuntime: @unchecked Sendable {
    private struct ResolvedInvocation {
        let toolID: String
        let toolVersion: String
        let toolPurpose: String
        let declaredRisk: Risk
        let runtimeRiskPolicy: RuntimeRiskPolicy
        let plannedActionRisks: [Risk]
        let input: Data
        let shellInvocation: HookInvocation?
        let destination: String?
        let dataLeavingDevice: DataLeavingDevice
        let reversibility: Reversibility
        let arguments: [ConfirmationArgument]
        let actionSummary: String
    }

    /// A resolved workflow / quick action awaiting execution: its ordered plan and
    /// the exact shell invocation for its hook step, if it has exactly one. A plan
    /// with more than one hook step never carries an invocation, so the allowlist
    /// can never waive confirmation for it (stricter, FR-SAF-03).
    private struct ResolvedWorkflow {
        let workflowID: String
        let label: String
        let schemaVersion: String
        let plan: ModePlan
        let hookInvocations: [String: HookInvocation]
        let shellInvocationForPolicy: HookInvocation?
    }

    private enum PendingWork {
        case tool(ResolvedInvocation)
        case workflow(ResolvedWorkflow)
    }

    private struct PendingExecution {
        var machine: CommandLifecycleMachine
        let work: PendingWork
    }

    private let lock = NSLock()
    private let parser: DirectCommandParser
    /// The shared live reference catalog (NIC-146): the parser reads through it and,
    /// on the macOS shell, so do the app/url capability target maps. Reloading it
    /// makes a mid-session mint resolvable everywhere at once — no relaunch.
    private let referenceStore: CommandReferenceStore
    private let registry: ToolRegistry
    private let policy: PolicyEngine
    private let executor: ToolExecutor
    /// The shared live-overrides holder (NIC-137): both `policy` and `executor` evaluate
    /// through this box, so writing it re-arms confirmation everywhere at once. `nil` when
    /// composed with a static policy (tests, non-settings hosts).
    private let policyOverridesBox: PolicyOverridesBox?
    private let coordinator: ConfirmationCoordinator
    private let factory: CommandFactory
    private let hookCatalog: HookCatalog
    private let modePlanner: (any ActionPlanner)?
    private let clock: any TimeSource
    private let commandSink: @Sendable (CommandEnvelope) -> Void
    private let sink: @Sendable (CommandLifecycleEvent) -> Void
    private let toolCallSink: @Sendable (String, Data) -> Void
    private let actionProgressSink: @Sendable (WorkflowActionProgress) -> Void
    private var pending: [String: PendingExecution] = [:]

    public init(
        registry: ToolRegistry,
        policy: PolicyEngine = PolicyEngine(),
        policyOverridesBox: PolicyOverridesBox? = nil,
        phase: ExecutionPhase = .preMac,
        coordinator: ConfirmationCoordinator,
        factory: CommandFactory,
        references: CommandReferences,
        referenceStore: CommandReferenceStore? = nil,
        hookCatalog: HookCatalog = HookCatalog(),
        modePlanner: (any ActionPlanner)? = nil,
        clock: any TimeSource = SystemClock(),
        commandSink: @escaping @Sendable (CommandEnvelope) -> Void = { _ in },
        sink: @escaping @Sendable (CommandLifecycleEvent) -> Void = { _ in },
        toolCallSink: @escaping @Sendable (String, Data) -> Void = { _, _ in },
        actionProgressSink: @escaping @Sendable (WorkflowActionProgress) -> Void = { _ in }
    ) {
        // A shared store injected (macOS shell) is read by the native capability
        // maps too, so one reload updates parser + capabilities together; absent one
        // (CLI, tests) the parser gets its own — still correct, just not externally
        // reloadable.
        let store = referenceStore ?? CommandReferenceStore(references)
        self.referenceStore = store
        self.parser = DirectCommandParser(referenceStore: store)
        self.registry = registry
        self.policy = policy
        self.policyOverridesBox = policyOverridesBox
        self.executor = ToolExecutor(registry: registry, policy: policy, phase: phase, clock: clock)
        self.coordinator = coordinator
        self.factory = factory
        self.hookCatalog = hookCatalog
        self.modePlanner = modePlanner
        self.clock = clock
        self.commandSink = commandSink
        self.sink = sink
        self.toolCallSink = toolCallSink
        self.actionProgressSink = actionProgressSink
    }

    /// Live-updates the "Ask before all actions" tightening (NIC-137): the policy engine
    /// and its executor share one overrides box, so this re-arms (or relaxes back to
    /// descriptor policy) confirmation immediately — no relaunch. Stricter-only: it can
    /// only raise `local_write`+ actions to require confirmation, never weaken policy. A
    /// no-op when composed with a static policy (no box).
    public func updateConfirmAllActions(_ enabled: Bool) {
        policyOverridesBox?.current = enabled ? .confirmEveryAction : PolicyOverrides()
    }

    /// Live-reloads the reference catalog (NIC-146): after a mid-session mint (e.g. the
    /// user adds a URL) the parser resolves the new `open <id>` immediately, and — when
    /// composed with a shared store (the macOS shell) — the app/url capability target
    /// maps see it too. Mirrors ``updateConfirmAllActions``: swap the shared box, no
    /// relaunch.
    public func updateReferences(_ references: CommandReferences) {
        referenceStore.reload(references)
    }

    /// Parses and runs one line of input. An allowed command executes; a
    /// confirmation-required command pauses and returns its disclosure; a denied
    /// command ends `failed` without reaching a handler.
    public func submit(_ rawInput: String, source: CommandSource) async -> CommandRuntimeOutcome {
        switch parser.parse(rawInput) {
        case let .unrecognized(unrecognized):
            return .rejected(reason: describe(unrecognized.reason), suggestions: unrecognized.suggestions)
        case let .ambiguous(ambiguous):
            return .rejected(
                reason: "Ambiguous reference '\(ambiguous.token)' for '\(ambiguous.verb)'.",
                suggestions: ambiguous.candidates.map { "\($0.kind):\($0.id)" }
            )
        case let .parsed(intent):
            let envelope = factory.makeEnvelope(
                source: source,
                rawInput: rawInput,
                privacy: CommandPrivacy(cloudPolicy: .deny, sensitivity: .sensitivityPrivate)
            )
            return await start(envelope: envelope, intent: intent)
        }
    }

    /// Resolves a confirmation. Approve runs the pending command; cancel ends it;
    /// review or any rejection (replay, expiry, plan change) does not execute.
    public func decide(token: ConfirmationToken, decision: ConfirmationDecision) async -> CommandRuntimeOutcome {
        switch coordinator.decide(token: token, decision: decision) {
        case let .approved(_, commandID):
            guard var entry = take(commandID) else {
                return .rejected(reason: "No pending command for \(commandID).", suggestions: [])
            }
            switch entry.work {
            case let .tool(invocation):
                return await run(commandID, &entry.machine, invocation)
            case let .workflow(workflow):
                return await runWorkflow(commandID, &entry.machine, workflow)
            }
        case let .cancelled(_, commandID):
            guard var entry = take(commandID) else {
                return .rejected(reason: "No pending command for \(commandID).", suggestions: [])
            }
            emit(&entry.machine) { try $0.cancel(message: "Confirmation cancelled.") }
            return .completed(commandID: commandID, status: entry.machine.status ?? .cancelled, result: nil)
        case let .reviewed(_, commandID):
            return .rejected(reason: "Confirmation \(commandID) reviewed; a final decision is still required.", suggestions: [])
        case let .rejected(rejection):
            return .rejected(reason: "Confirmation \(rejection.rawValue).", suggestions: [])
        }
    }

    // MARK: - Internals

    private func start(envelope: CommandEnvelope, intent: CommandIntent) async -> CommandRuntimeOutcome {
        // Surface the command before its first event so a durable sink can create
        // the command row the events reference (FK ordering); the envelope carries
        // the source and privacy the events do not.
        commandSink(envelope)
        var machine = CommandLifecycleMachine(commandId: envelope.id, factory: factory)
        emit(&machine) { try $0.markReceived(message: "Command received.") }
        emit(&machine) { try $0.markPlanned(message: "Command planned.") }

        if case let .runAction(actionID) = intent {
            return await startWorkflow(envelope: envelope, actionID: actionID, machine: &machine)
        }

        guard let resolved = resolve(intent) else {
            // No registered tool for this intent (e.g. mode.apply before NIC-33-C).
            // Reach the terminal through the legal running → failed edge.
            emit(&machine) { try $0.markRunning(message: "Running.") }
            emit(&machine) {
                try $0.markFailed(
                    error: lifecycleError(.unavailableCapability, "tool.unavailable", "No tool is available for this command yet."),
                    message: "No tool is available for this command yet."
                )
            }
            return .completed(commandID: envelope.id, status: machine.status ?? .failed, result: nil)
        }

        let evaluation = policy.evaluate(
            PolicyRequest(
                toolID: resolved.toolID,
                declaredRisk: resolved.declaredRisk,
                runtimeRiskPolicy: resolved.runtimeRiskPolicy,
                plannedActionRisks: resolved.plannedActionRisks,
                shellInvocation: resolved.shellInvocation
            )
        )

        if evaluation.decision == .requireConfirmation {
            emit(&machine) { try $0.requireConfirmation(message: "Awaiting confirmation.") }
            let request = coordinator.requestConfirmation(
                plan: makePlan(commandID: envelope.id, resolved: resolved, risk: evaluation.governingRisk, policyReason: evaluation.reason)
            )
            store(envelope.id, machine: machine, work: .tool(resolved))
            return .awaitingConfirmation(commandID: envelope.id, disclosure: request.disclosure, token: request.token)
        }

        // Allow or deny both proceed to `run`: the executor re-applies policy and
        // returns a `denied` result without invoking the handler (AC-29.1), so a
        // denied command ends `failed` via the legal running → failed edge rather
        // than an illegal planned → failed transition.
        return await run(envelope.id, &machine, resolved)
    }

    /// Resolves a workflow / quick action into its ordered plan, evaluates policy
    /// over the plan's aggregate risk (FR-MOD-03: never weaker than the strictest
    /// step), and executes it — pausing for one aggregate confirmation when the
    /// governing risk requires it. Steps then run without re-prompting: the
    /// approval covered the disclosed plan, and the executor still denies any
    /// policy-denied tool (AC-29.1), so this can gate less than policy but never
    /// bypass a denial.
    private func startWorkflow(
        envelope: CommandEnvelope, actionID: String, machine: inout CommandLifecycleMachine
    ) async -> CommandRuntimeOutcome {
        guard let planner = modePlanner else {
            emit(&machine) { try $0.markRunning(message: "Running.") }
            emit(&machine) {
                try $0.markFailed(
                    error: lifecycleError(.unavailableCapability, "workflow.no_planner", "No action planner is composed."),
                    message: "No action planner is composed."
                )
            }
            return .completed(commandID: envelope.id, status: machine.status ?? .failed, result: nil)
        }

        let plan: ModePlan
        do {
            plan = try planner.plan(actionID: actionID)
        } catch {
            let message = workflowResolveMessage(error, actionID: actionID)
            emit(&machine) { try $0.markRunning(message: "Running.") }
            emit(&machine) {
                try $0.markFailed(
                    error: lifecycleError(.invalidInput, "workflow.unresolvable", message),
                    message: message
                )
            }
            return .completed(commandID: envelope.id, status: machine.status ?? .failed, result: nil)
        }

        // Hook steps execute with their exact configured invocation. Exactly one
        // hook step also passes its invocation to policy so the user allowlist can
        // apply (FR-SAF-03); more than one always confirms.
        var hookInvocations: [String: HookInvocation] = [:]
        for action in plan.actions where action.kind == "hook.run" {
            if let input = action.input,
               let decoded = try? CerebralHelmHookRunInput(data: input),
               let invocation = hookCatalog.invocation(for: decoded.hookID) {
                hookInvocations[action.actionID] = invocation
            }
        }
        let workflow = ResolvedWorkflow(
            workflowID: actionID,
            label: actionID,
            schemaVersion: "1.0.0",
            plan: plan,
            hookInvocations: hookInvocations,
            shellInvocationForPolicy: hookInvocations.count == 1 ? hookInvocations.values.first : nil
        )

        let evaluation = policy.evaluate(
            PolicyRequest(
                toolID: actionID,
                declaredRisk: .readOnly,
                runtimeRiskPolicy: .highestPlannedAction,
                plannedActionRisks: plan.actions.map(\.risk),
                shellInvocation: workflow.shellInvocationForPolicy
            )
        )

        if evaluation.decision == .requireConfirmation {
            emit(&machine) { try $0.requireConfirmation(message: "Awaiting confirmation.") }
            let request = coordinator.requestConfirmation(
                plan: makeWorkflowPlan(commandID: envelope.id, workflow: workflow, risk: evaluation.governingRisk, policyReason: evaluation.reason)
            )
            store(envelope.id, machine: machine, work: .workflow(workflow))
            return .awaitingConfirmation(commandID: envelope.id, disclosure: request.disclosure, token: request.token)
        }
        return await runWorkflow(envelope.id, &machine, workflow)
    }

    /// Executes a resolved plan's actions in order through the tool executor.
    /// A failed or unavailable step never aborts the remaining steps or erases
    /// prior successes (FR-MOD-04); each step's result is recorded as its own
    /// tool call. The command succeeds when at least one step succeeded and fails
    /// only when none did.
    private func runWorkflow(
        _ commandID: String, _ machine: inout CommandLifecycleMachine, _ workflow: ResolvedWorkflow
    ) async -> CommandRuntimeOutcome {
        emit(&machine) { try $0.markRunning(message: "Running \(workflow.plan.actions.count) actions.") }

        let total = workflow.plan.actions.count
        func progress(_ action: PlannedAction, _ index: Int, _ status: WorkflowActionProgress.Status, _ message: String? = nil) {
            actionProgressSink(WorkflowActionProgress(
                commandID: commandID, workflowID: workflow.workflowID,
                actionID: action.actionID, kind: action.kind,
                status: status, index: index + 1, total: total, message: message
            ))
        }

        var succeeded = 0, failed = 0, unavailable = 0
        for (index, action) in workflow.plan.actions.enumerated() {
            guard action.status != .unavailable else {
                unavailable += 1
                progress(action, index, .unavailable, action.message)
                continue
            }
            progress(action, index, .running)
            let startedAt = clock.now()
            let result = await executor.execute(ToolInvocation(
                toolID: action.kind,
                input: action.input ?? Data("{}".utf8),
                shellInvocation: workflow.hookInvocations[action.actionID]
            ))
            recordToolCall(commandID: commandID, toolID: action.kind, input: action.input ?? Data("{}".utf8), result: result, startedAt: startedAt, completedAt: clock.now())

            switch result.status {
            case .success, .partialSuccess:
                succeeded += 1
                progress(action, index, .succeeded)
            case .cancelled:
                progress(action, index, .cancelled, result.error?.message)
                emit(&machine) { try $0.cancel(message: "Cancelled after \(succeeded) of \(workflow.plan.actions.count) actions.") }
                return .completed(commandID: commandID, status: machine.status ?? .cancelled, result: nil)
            case .unavailable:
                unavailable += 1
                progress(action, index, .unavailable, result.error?.message)
            default:
                failed += 1
                progress(action, index, .failed, result.error?.message)
            }
        }

        let summary = "\(succeeded) succeeded, \(failed) failed, \(unavailable) unavailable of \(workflow.plan.actions.count) actions."
        if succeeded > 0 {
            emit(&machine) { try $0.markSucceeded(message: summary) }
        } else {
            emit(&machine) {
                try $0.markFailed(
                    error: lifecycleError(.internalFailure, "workflow.no_actions_succeeded", summary),
                    message: summary
                )
            }
        }
        return .completed(commandID: commandID, status: machine.status ?? .failed, result: nil)
    }

    private func workflowResolveMessage(_ error: Error, actionID: String) -> String {
        switch error {
        case ActionPlannerError.unknownAction:
            return "No workflow is configured for '\(actionID)'."
        case let ActionPlannerError.unsupportedTool(action, tool):
            return "Workflow '\(action)' names unsupported tool '\(tool)'."
        case let ActionPlannerError.invalidStepInput(action, step, tool, _):
            return "Workflow '\(action)' step '\(step)' has invalid input for tool '\(tool)'."
        default:
            return "Workflow '\(actionID)' could not be resolved."
        }
    }

    private func makeWorkflowPlan(
        commandID: String, workflow: ResolvedWorkflow, risk: Risk, policyReason: String
    ) -> ConfirmationPlan {
        ConfirmationPlan(
            commandID: commandID,
            toolID: workflow.workflowID,
            toolVersion: workflow.schemaVersion,
            toolPurpose: "Run the configured workflow '\(workflow.workflowID)'.",
            risk: risk,
            destination: nil,
            accountOrService: nil,
            dataLeavingDevice: .none,
            reversibility: workflow.plan.actions.contains { $0.risk == .shell } ? .unknown : .reversible,
            arguments: workflow.plan.actions.map {
                ConfirmationArgument(name: $0.actionID, value: $0.kind, sensitive: false)
            },
            actionSummary: "Run workflow '\(workflow.workflowID)' (\(workflow.plan.actions.count) actions).",
            policyReason: policyReason
        )
    }

    private func run(_ commandID: String, _ machine: inout CommandLifecycleMachine, _ resolved: ResolvedInvocation) async -> CommandRuntimeOutcome {
        emit(&machine) { try $0.markRunning(message: "Running.") }
        let startedAt = clock.now()
        let result = await executor.execute(
            ToolInvocation(toolID: resolved.toolID, input: resolved.input, shellInvocation: resolved.shellInvocation)
        )
        recordToolCall(commandID: commandID, resolved: resolved, result: result, startedAt: startedAt, completedAt: clock.now())

        switch result.status {
        case .success, .partialSuccess:
            emit(&machine) { try $0.markSucceeded(message: "Completed.") }
        case .cancelled:
            emit(&machine) { try $0.cancel(message: "Cancelled.") }
        default:
            let error = result.error ?? StructuredError(category: .internalFailure, code: "tool.failed", details: nil, message: "Tool failed.", remediation: nil)
            emit(&machine) {
                try $0.markFailed(error: lifecycleError(error.category, error.code, error.message), message: error.message)
            }
        }
        return .completed(commandID: commandID, status: machine.status ?? .failed, result: result)
    }

    private func resolve(_ intent: CommandIntent) -> ResolvedInvocation? {
        switch intent {
        case let .openApp(reference):
            return make(
                toolID: "app.open",
                input: try? CerebralHelmAppOpenInput(appID: reference.id).jsonData(),
                destination: reference.target,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "application", value: reference.label, sensitive: false)],
                actionSummary: "Open application \(reference.label)."
            )
        case let .openURL(reference):
            return make(
                toolID: "url.open",
                input: try? CerebralHelmURLOpenInput(urlID: reference.id).jsonData(),
                destination: reference.target,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "url", value: reference.target, sensitive: false)],
                actionSummary: "Open URL \(reference.label)."
            )
        case let .captureNote(text):
            // The body is the only place free text lives, and it is redacted in
            // logs via the descriptor's `/body` path. Title, arguments, and the
            // disclosure summary are kept content-free so a secret in the note
            // body cannot leak through an unredacted field (NIC-34).
            return make(
                toolID: "note.capture",
                input: try? CerebralHelmNoteCaptureInput(body: text, kind: "note", project: nil, sensitivity: nil, title: "Captured note").jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "kind", value: "note", sensitive: false)],
                actionSummary: "Capture a note."
            )
        case let .openProject(repoPath):
            // Open a repository directory in the configured editor (NIC-131). The
            // descriptor's `local_write` risk routes it through a policy-owned
            // confirmation before the editor launches; the adapter constrains the path
            // to the projects root. The repo folder name is shown in the disclosure (not
            // sensitive) so the user sees which repository will open.
            let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
            return make(
                toolID: "project.open",
                input: try? CerebralHelmProjectOpenInput(repoPath: repoPath).jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "repository", value: repoPath, sensitive: false)],
                actionSummary: "Open \(repoName.isEmpty ? "repository" : repoName) in the editor."
            )
        case let .searchNotes(query):
            return make(
                toolID: "note.search",
                input: try? CerebralHelmNoteSearchInput(limit: nil, query: query).jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [],
                actionSummary: "Search notes for \(query)."
            )
        case .listApps:
            return make(
                toolID: "apps.list",
                input: try? CerebralHelmAppsListInput(includeIcons: true).jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [],
                actionSummary: "List installed applications."
            )
        case let .runHook(reference):
            return make(
                toolID: "hook.run",
                input: try? CerebralHelmHookRunInput(hookID: reference.id).jsonData(),
                shellInvocation: hookCatalog.invocation(for: reference.id),
                destination: reference.target,
                dataLeavingDevice: .none,
                reversibility: .unknown,
                arguments: [ConfirmationArgument(name: "hook", value: reference.label, sensitive: false)],
                actionSummary: "Run hook \(reference.label)."
            )
        case let .applyMode(modeID):
            // A mode switch changes the active mode, context, and dashboard
            // surface; it runs no workflow steps (workspace re-scope, NIC-85).
            // Its risk is the descriptor's local_write — there are no planned
            // actions to aggregate.
            return make(
                toolID: "mode.apply",
                input: try? CerebralHelmModeApplyInput(modeID: modeID).jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "mode", value: modeID, sensitive: false)],
                actionSummary: "Switch to mode \(modeID)."
            )
        case .runSpeedTest:
            // A single read-only measurement (NIC-135). It talks to Apple's test
            // servers, so it is honest about metadata leaving the device — but as a
            // fixed, non-mutating diagnostic it runs without confirmation
            // (descriptor risk `read_only`), unlike an arbitrary `hook.run`.
            return make(
                toolID: "network.speed.test",
                input: Data("{}".utf8),
                destination: nil,
                dataLeavingDevice: .metadataOnly,
                reversibility: .reversible,
                arguments: [],
                actionSummary: "Measure internet speed."
            )
        case .quitAllApps:
            // Quit every open application across all modes (NIC-143). Destructive
            // and not reversible — quitting an app can lose unsaved work — so the
            // descriptor's `destructive` risk routes it through a policy-owned
            // confirmation before anything terminates. Argument-free: the target set
            // is the running apps, discovered by the handler at execution time.
            return make(
                toolID: "apps.quitall",
                input: Data("{}".utf8),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .notReversible,
                arguments: [],
                actionSummary: "Quit every open application across all modes."
            )
        case .runAction:
            // Workflows resolve through startWorkflow, never through the
            // single-tool path.
            return nil
        }
    }

    private func make(
        toolID: String,
        input: Data?,
        plannedActionRisks: [Risk] = [],
        shellInvocation: HookInvocation? = nil,
        destination: String?,
        dataLeavingDevice: DataLeavingDevice,
        reversibility: Reversibility,
        arguments: [ConfirmationArgument],
        actionSummary: String
    ) -> ResolvedInvocation? {
        guard let tool = registry.tool(toolID), let input else { return nil }

        // Enforce descriptor-declared redaction on the confirmation disclosure
        // itself, not just the tool-call log. Any value the descriptor marks as a
        // redaction path (e.g. note.search `/query`) is extracted from the input
        // and masked wherever it appears verbatim in the action summary or an
        // argument value. This runs before makePlan/PlanHash, so the hash and the
        // disclosure are computed over the already-redacted form. The mechanism is
        // generic over the descriptor; functionally only note.search changes today
        // (its summary becomes "Search notes for [REDACTED]").
        //
        // DECISION (NIC-110): actionSummary may carry free text, but only what
        // survives this pass — a descriptor-covered value must never reach the
        // disclosure in the clear, so callers no longer rely on hand-written
        // content-free summaries to stay secret-free.
        let coveredValues = SchemaRedactor.valuesAtPaths(input, paths: tool.descriptor.logging.redactionPaths)
        let redactedArguments = arguments.map { argument in
            ConfirmationArgument(
                name: argument.name,
                value: redactCoveredValues(in: argument.value, covered: coveredValues),
                sensitive: argument.sensitive
            )
        }
        let redactedActionSummary = redactCoveredValues(in: actionSummary, covered: coveredValues)

        return ResolvedInvocation(
            toolID: toolID,
            toolVersion: tool.descriptor.version,
            toolPurpose: tool.descriptor.purpose,
            declaredRisk: tool.risk,
            runtimeRiskPolicy: tool.descriptor.runtimeRiskPolicy,
            plannedActionRisks: plannedActionRisks,
            input: input,
            shellInvocation: shellInvocation,
            destination: destination,
            dataLeavingDevice: dataLeavingDevice,
            reversibility: reversibility,
            arguments: redactedArguments,
            actionSummary: redactedActionSummary
        )
    }

    /// Replaces every verbatim occurrence of a descriptor-covered value with the
    /// redaction marker. Longer values are masked first so a value that contains
    /// a shorter one is not partially revealed; empty covered values are ignored.
    private func redactCoveredValues(in text: String, covered: [String]) -> String {
        var result = text
        for value in covered.sorted(by: { $0.count > $1.count }) where !value.isEmpty {
            result = result.replacingOccurrences(of: value, with: SchemaRedactor.marker)
        }
        return result
    }

    private func makePlan(commandID: String, resolved: ResolvedInvocation, risk: Risk, policyReason: String) -> ConfirmationPlan {
        ConfirmationPlan(
            commandID: commandID,
            toolID: resolved.toolID,
            toolVersion: resolved.toolVersion,
            toolPurpose: resolved.toolPurpose,
            risk: risk,
            destination: resolved.destination,
            accountOrService: nil,
            dataLeavingDevice: resolved.dataLeavingDevice,
            reversibility: resolved.reversibility,
            arguments: resolved.arguments,
            actionSummary: resolved.actionSummary,
            policyReason: policyReason
        )
    }

    /// Emits a redacted ``CerebralHelmToolResult`` to the tool-call sink. Input
    /// and output are redacted with the descriptor's declared paths before they
    /// leave the runtime (NIC-34), so no secret reaches the operational log.
    private func recordToolCall(commandID: String, resolved: ResolvedInvocation, result: ToolExecutionResult, startedAt: Date, completedAt: Date) {
        recordToolCall(commandID: commandID, toolID: resolved.toolID, input: resolved.input, result: result, startedAt: startedAt, completedAt: completedAt)
    }

    private func recordToolCall(commandID: String, toolID: String, input: Data, result: ToolExecutionResult, startedAt: Date, completedAt: Date) {
        guard let descriptor = registry.tool(toolID)?.descriptor else { return }
        let record = ToolCallRecorder.record(
            descriptor: descriptor,
            input: input,
            result: result,
            startedAt: startedAt,
            completedAt: completedAt
        )
        if let data = try? record.jsonData() {
            toolCallSink(commandID, data)
        }
    }

    private func emit(_ machine: inout CommandLifecycleMachine, _ transition: (inout CommandLifecycleMachine) throws -> CommandLifecycleEvent) {
        guard let event = try? transition(&machine) else { return }
        sink(event)
    }

    private func lifecycleError(_ category: CerebralContracts.Category, _ code: String, _ message: String) -> CerebralHelmCommandLifecycleEventError {
        CerebralHelmCommandLifecycleEventError(category: category, code: code, details: nil, message: message, remediation: nil)
    }

    private func describe(_ reason: UnrecognizedInput.Reason) -> String {
        switch reason {
        case .emptyInput: return "No command entered."
        case let .unknownVerb(verb): return "Unknown command '\(verb)'."
        case let .missingArgument(verb): return "Missing argument for '\(verb)'."
        case let .unresolvedReference(verb, token): return "Unknown \(verb) reference '\(token)'."
        }
    }

    private func store(_ commandID: String, machine: CommandLifecycleMachine, work: PendingWork) {
        lock.lock(); defer { lock.unlock() }
        pending[commandID] = PendingExecution(machine: machine, work: work)
    }

    private func take(_ commandID: String) -> PendingExecution? {
        lock.lock(); defer { lock.unlock() }
        defer { pending[commandID] = nil }
        return pending[commandID]
    }
}
