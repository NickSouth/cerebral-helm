import Foundation
import CerebralContracts
import CerebralShared

/// A tool result status. Aliases the generated `StatusElement` so the executor
/// speaks the same vocabulary as the tool-result contract.
public typealias ToolResultStatus = StatusElement

/// A resolved request to execute one tool: the tool id, its already-parsed input
/// bytes, the concrete shell invocation (for shell tools), and the caller's
/// confirmation hint. The risk class is taken from the validated descriptor, not
/// from here, so a caller cannot understate risk.
public struct ToolInvocation: Sendable {
    public let toolID: String
    public let input: Data
    public let shellInvocation: HookInvocation?
    public let callerRequestedConfirmation: Bool?

    public init(
        toolID: String,
        input: Data,
        shellInvocation: HookInvocation? = nil,
        callerRequestedConfirmation: Bool? = nil
    ) {
        self.toolID = toolID
        self.input = input
        self.shellInvocation = shellInvocation
        self.callerRequestedConfirmation = callerRequestedConfirmation
    }
}

/// The single structured terminal result of executing a tool (FR-TOL-03). Exactly
/// one is produced per invocation, with a status that distinguishes success,
/// denial, timeout, cancellation, unavailability, and failure (FR-TOL-06).
public struct ToolExecutionResult: Sendable {
    public let toolID: String
    public let status: ToolResultStatus
    /// Output bytes on success; `nil` otherwise.
    public let output: Data?
    /// Structured error on any non-success status; `nil` on success.
    public let error: StructuredError?
    public let durationMs: Int

    public init(toolID: String, status: ToolResultStatus, output: Data?, error: StructuredError?, durationMs: Int) {
        self.toolID = toolID
        self.status = status
        self.output = output
        self.error = error
        self.durationMs = durationMs
    }
}

/// Executes a validated tool: applies policy before invocation, runs the bound
/// handler under a timeout with cooperative cancellation, and returns exactly one
/// structured result (NIC-29). It holds no lock across the handler call and is
/// fully asynchronous, so a long-running tool never blocks other work (NFR-05,
/// AC-29.3).
public struct ToolExecutor: Sendable {
    private let registry: ToolRegistry
    private let policy: PolicyEngine
    private let clock: any TimeSource

    public init(registry: ToolRegistry, policy: PolicyEngine, clock: any TimeSource = SystemClock()) {
        self.registry = registry
        self.policy = policy
        self.clock = clock
    }

    public func execute(_ invocation: ToolInvocation) async -> ToolExecutionResult {
        let started = clock.now()
        func elapsedMs() -> Int { max(0, Int(clock.now().timeIntervalSince(started) * 1000)) }

        guard
            let tool = registry.tool(invocation.toolID),
            let handler = registry.handler(for: invocation.toolID)
        else {
            return ToolExecutionResult(
                toolID: invocation.toolID,
                status: .unavailable,
                output: nil,
                error: structured(.unavailableCapability, "tool.unknown", "Tool '\(invocation.toolID)' is not registered."),
                durationMs: elapsedMs()
            )
        }

        // Availability gate (NIC-111). A tool the descriptor (after any stricter
        // overlay) marks unavailable in the current pre-Mac phase must not run, no
        // matter how it was reached. This is distinct from `tool.unknown`
        // (unregistered): the tool exists and is bound, but its declared
        // availability forbids execution in this phase, so the handler — including
        // shell-class tools like hook.run — is never invoked.
        guard tool.availableInPreMac else {
            return ToolExecutionResult(
                toolID: tool.id,
                status: .unavailable,
                output: nil,
                error: structured(
                    .unavailableCapability,
                    "tool.unavailable_in_phase",
                    "Tool '\(tool.id)' is not available in the current phase."
                ),
                durationMs: elapsedMs()
            )
        }

        // Policy gate. A denied call never reaches the handler (AC-29.1).
        let evaluation = policy.evaluate(
            PolicyRequest(
                toolID: tool.id,
                declaredRisk: tool.risk,
                runtimeRiskPolicy: tool.descriptor.runtimeRiskPolicy,
                shellInvocation: invocation.shellInvocation,
                callerRequestedConfirmation: invocation.callerRequestedConfirmation
            )
        )
        if evaluation.decision == .deny {
            return ToolExecutionResult(
                toolID: tool.id,
                status: .denied,
                output: nil,
                error: structured(.policyDenied, evaluation.reasonCode, evaluation.reason),
                durationMs: elapsedMs()
            )
        }
        // A `requireConfirmation` decision is resolved by the confirmation
        // coordinator (NIC-31) before `execute` is called; reaching here means the
        // command is cleared to run.

        let timeoutMs = tool.effectiveTimeoutMs
        do {
            switch try await runWithTimeout(timeoutMs: timeoutMs, work: { try await handler.execute(input: invocation.input) }) {
            case let .completed(output):
                return ToolExecutionResult(toolID: tool.id, status: .success, output: output, error: nil, durationMs: elapsedMs())
            case .timedOut:
                return ToolExecutionResult(
                    toolID: tool.id,
                    status: .timeout,
                    output: nil,
                    error: structured(.timeout, "tool.timeout", "Tool '\(tool.id)' exceeded its \(timeoutMs)ms timeout."),
                    durationMs: elapsedMs()
                )
            }
        } catch is CancellationError {
            return ToolExecutionResult(
                toolID: tool.id,
                status: .cancelled,
                output: nil,
                error: structured(.cancelled, "tool.cancelled", "Tool '\(tool.id)' was cancelled before completing."),
                durationMs: elapsedMs()
            )
        } catch let handlerError as ToolHandlerError {
            let (status, category) = Self.classify(handlerError)
            return ToolExecutionResult(
                toolID: tool.id,
                status: status,
                output: nil,
                error: structured(category, Self.code(handlerError), Self.message(handlerError)),
                durationMs: elapsedMs()
            )
        } catch {
            return ToolExecutionResult(
                toolID: tool.id,
                status: .failure,
                output: nil,
                error: structured(.internalFailure, "tool.internal_error", "Tool '\(tool.id)' failed unexpectedly."),
                durationMs: elapsedMs()
            )
        }
    }

    // MARK: - Timeout

    private enum TimedOutcome {
        case completed(Data)
        case timedOut
    }

    /// Races the handler against a deadline. If the handler wins, its output is
    /// returned and the timer is cancelled. If the deadline wins, the handler is
    /// cancelled and `.timedOut` is returned. External cancellation propagates as
    /// `CancellationError` from the deadline sleep, keeping timeout (the timer
    /// completing normally) distinct from cancellation (AC-29.2).
    private func runWithTimeout(
        timeoutMs: Int,
        work: @escaping @Sendable () async throws -> Data
    ) async throws -> TimedOutcome {
        try await withThrowingTaskGroup(of: TimedOutcome.self) { group in
            group.addTask { .completed(try await work()) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                return .timedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    // MARK: - Error mapping

    private func structured(_ category: Category, _ code: String, _ message: String) -> StructuredError {
        StructuredError(category: category, code: code, details: nil, message: message, remediation: nil)
    }

    private static func classify(_ error: ToolHandlerError) -> (ToolResultStatus, Category) {
        switch error {
        case .invalidInput: return (.failure, .invalidInput)
        case .invalidOutput: return (.failure, .adapterContractFailure)
        case .unavailable: return (.unavailable, .unavailableCapability)
        case .permissionDenied: return (.denied, .permissionDenied)
        case .providerFailure: return (.failure, .providerFailure)
        }
    }

    private static func code(_ error: ToolHandlerError) -> String {
        switch error {
        case .invalidInput: return "tool.invalid_input"
        case .invalidOutput: return "tool.invalid_output"
        case .unavailable: return "tool.unavailable"
        case .permissionDenied: return "tool.permission_denied"
        case .providerFailure: return "tool.provider_failure"
        }
    }

    private static func message(_ error: ToolHandlerError) -> String {
        switch error {
        case let .invalidInput(message),
             let .invalidOutput(message),
             let .unavailable(message),
             let .permissionDenied(message),
             let .providerFailure(message):
            return message
        }
    }
}
