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
    private let sink: @Sendable (CommandLifecycleEvent) -> Void
    private var pending: [String: PendingExecution] = [:]

    public init(
        registry: ToolRegistry,
        policy: PolicyEngine = PolicyEngine(),
        coordinator: ConfirmationCoordinator,
        factory: CommandFactory,
        references: CommandReferences,
        hookCatalog: HookCatalog = HookCatalog(),
        clock: any TimeSource = SystemClock(),
        sink: @escaping @Sendable (CommandLifecycleEvent) -> Void = { _ in }
    ) {
        self.parser = DirectCommandParser(references: references)
        self.registry = registry
        self.policy = policy
        self.executor = ToolExecutor(registry: registry, policy: policy, clock: clock)
        self.coordinator = coordinator
        self.factory = factory
        self.hookCatalog = hookCatalog
        self.sink = sink
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
                shellInvocation: resolved.shellInvocation
            )
        )

        if evaluation.decision == .requireConfirmation {
            emit(&machine) { try $0.requireConfirmation(message: "Awaiting confirmation.") }
            let request = coordinator.requestConfirmation(
                plan: makePlan(commandID: envelope.id, resolved: resolved, policyReason: evaluation.reason)
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
        let result = await executor.execute(
            ToolInvocation(toolID: resolved.toolID, input: resolved.input, shellInvocation: resolved.shellInvocation)
        )

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
            let title = noteTitle(from: text)
            return make(
                toolID: "note.capture",
                input: try? CerebralHelmNoteCaptureInput(body: text, kind: "note", project: nil, sensitivity: nil, title: title).jsonData(),
                destination: nil,
                dataLeavingDevice: .none,
                reversibility: .reversible,
                arguments: [ConfirmationArgument(name: "title", value: title, sensitive: false)],
                actionSummary: "Capture note \(title)."
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
        case .applyMode:
            // mode.apply is wired by NIC-33-C (Increment 9).
            return nil
        }
    }

    private func make(
        toolID: String,
        input: Data?,
        shellInvocation: HookInvocation? = nil,
        destination: String?,
        dataLeavingDevice: DataLeavingDevice,
        reversibility: Reversibility,
        arguments: [ConfirmationArgument],
        actionSummary: String
    ) -> ResolvedInvocation? {
        guard let tool = registry.tool(toolID), let input else { return nil }
        return ResolvedInvocation(
            toolID: toolID,
            toolVersion: tool.descriptor.version,
            toolPurpose: tool.descriptor.purpose,
            declaredRisk: tool.risk,
            runtimeRiskPolicy: tool.descriptor.runtimeRiskPolicy,
            input: input,
            shellInvocation: shellInvocation,
            destination: destination,
            dataLeavingDevice: dataLeavingDevice,
            reversibility: reversibility,
            arguments: arguments,
            actionSummary: actionSummary
        )
    }

    private func makePlan(commandID: String, resolved: ResolvedInvocation, policyReason: String) -> ConfirmationPlan {
        ConfirmationPlan(
            commandID: commandID,
            toolID: resolved.toolID,
            toolVersion: resolved.toolVersion,
            toolPurpose: resolved.toolPurpose,
            risk: resolved.declaredRisk,
            destination: resolved.destination,
            accountOrService: nil,
            dataLeavingDevice: resolved.dataLeavingDevice,
            reversibility: resolved.reversibility,
            arguments: resolved.arguments,
            actionSummary: resolved.actionSummary,
            policyReason: policyReason
        )
    }

    private func emit(_ machine: inout CommandLifecycleMachine, _ transition: (inout CommandLifecycleMachine) throws -> CommandLifecycleEvent) {
        guard let event = try? transition(&machine) else { return }
        sink(event)
    }

    private func lifecycleError(_ category: Category, _ code: String, _ message: String) -> CerebralHelmCommandLifecycleEventError {
        CerebralHelmCommandLifecycleEventError(category: category, code: code, details: nil, message: message, remediation: nil)
    }

    private func noteTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled note" : String(trimmed.prefix(60))
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
