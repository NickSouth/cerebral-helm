import Foundation
import CerebralContracts
import CerebralShared

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

    private struct PendingExecution {
        var machine: CommandLifecycleMachine
        let invocation: ResolvedInvocation
    }

    private let lock = NSLock()
    private let parser: DirectCommandParser
    private let registry: ToolRegistry
    private let policy: PolicyEngine
    private let executor: ToolExecutor
    private let coordinator: ConfirmationCoordinator
    private let factory: CommandFactory
    private let hookCatalog: HookCatalog
    private let modePlanner: (any ActionPlanner)?
    private let clock: any TimeSource
    private let commandSink: @Sendable (CommandEnvelope) -> Void
    private let sink: @Sendable (CommandLifecycleEvent) -> Void
    private let toolCallSink: @Sendable (String, Data) -> Void
    private var pending: [String: PendingExecution] = [:]

    public init(
        registry: ToolRegistry,
        policy: PolicyEngine = PolicyEngine(),
        coordinator: ConfirmationCoordinator,
        factory: CommandFactory,
        references: CommandReferences,
        hookCatalog: HookCatalog = HookCatalog(),
        modePlanner: (any ActionPlanner)? = nil,
        clock: any TimeSource = SystemClock(),
        commandSink: @escaping @Sendable (CommandEnvelope) -> Void = { _ in },
        sink: @escaping @Sendable (CommandLifecycleEvent) -> Void = { _ in },
        toolCallSink: @escaping @Sendable (String, Data) -> Void = { _, _ in }
    ) {
        self.parser = DirectCommandParser(references: references)
        self.registry = registry
        self.policy = policy
        self.executor = ToolExecutor(registry: registry, policy: policy, clock: clock)
        self.coordinator = coordinator
        self.factory = factory
        self.hookCatalog = hookCatalog
        self.modePlanner = modePlanner
        self.clock = clock
        self.commandSink = commandSink
        self.sink = sink
        self.toolCallSink = toolCallSink
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
            return await run(commandID, &entry.machine, entry.invocation)
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
            store(envelope.id, machine: machine, invocation: resolved)
            return .awaitingConfirmation(commandID: envelope.id, disclosure: request.disclosure, token: request.token)
        }

        // Allow or deny both proceed to `run`: the executor re-applies policy and
        // returns a `denied` result without invoking the handler (AC-29.1), so a
        // denied command ends `failed` via the legal running → failed edge rather
        // than an illegal planned → failed transition.
        return await run(envelope.id, &machine, resolved)
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
            guard let planner = modePlanner, let plan = try? planner.plan(modeID: modeID) else { return nil }
            return make(
                toolID: "mode.apply",
                input: try? CerebralHelmModeApplyInput(modeID: modeID).jsonData(),
                plannedActionRisks: plan.actions.map(\.risk),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .partiallyReversible,
                arguments: [ConfirmationArgument(name: "mode", value: modeID, sensitive: false)],
                actionSummary: "Apply mode \(modeID)."
            )
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
        guard let descriptor = registry.tool(resolved.toolID)?.descriptor else { return }
        let record = ToolCallRecorder.record(
            descriptor: descriptor,
            input: resolved.input,
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

    private func lifecycleError(_ category: Category, _ code: String, _ message: String) -> CerebralHelmCommandLifecycleEventError {
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

    private func store(_ commandID: String, machine: CommandLifecycleMachine, invocation: ResolvedInvocation) {
        lock.lock(); defer { lock.unlock() }
        pending[commandID] = PendingExecution(machine: machine, invocation: invocation)
    }

    private func take(_ commandID: String) -> PendingExecution? {
        lock.lock(); defer { lock.unlock() }
        defer { pending[commandID] = nil }
        return pending[commandID]
    }
}
