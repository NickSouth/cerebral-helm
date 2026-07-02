import Foundation
import CerebralContracts

/// A small receipt returned to the caller that submitted a command.
public struct CommandReceipt: Equatable, Sendable {
    public let commandId: String
    public let status: CommandStatus
}

/// A handle to an event subscription.
public struct CommandBusSubscription: Equatable, Sendable {
    fileprivate let token: Int
}

/// A failure raised when a command cannot be admitted to the bus.
public enum SubmissionError: Error, Equatable {
    /// The command's source is reserved and has no production producer yet.
    case reservedSource(CommandSource)

    public var structuredError: StructuredError {
        switch self {
        case let .reservedSource(source):
            return StructuredError(
                category: .policyDenied,
                code: "source.reserved_unsupported",
                details: nil,
                message: "Command source '\(source.rawValue)' is reserved and cannot be submitted yet.",
                remediation: nil
            )
        }
    }
}

/// In-process command bus.
///
/// All input sources converge here (ADR-002). The bus assigns each command a
/// lifecycle, drives it through the planning/execution stages, and fans the
/// resulting immutable events out to every subscriber in order. A subscriber
/// that throws is isolated and does not affect command state or other
/// subscribers. Cancellation is idempotent.
///
/// The bus is a lock-serialized class rather than an `actor`: events carry
/// `JSONAny` payloads that are not yet `Sendable`, and a synchronous,
/// internally-locked design delivers ordered events and fault isolation without
/// requiring every DTO to cross an actor boundary. It can migrate to an actor
/// once the generated contracts are `Sendable`.
///
/// Subscribers are invoked synchronously, off the lock, and must be thread-safe;
/// they should not re-enter the bus synchronously from within their handler.
public final class CommandBus: @unchecked Sendable {
    /// A subscriber receiving lifecycle events. May throw to signal its own
    /// failure; the bus isolates it.
    public typealias EventListener = @Sendable (CommandLifecycleEvent) throws -> Void

    // Reserved sources have contract fixtures but no production producer yet
    // (PRD §6.3). They are rejected at submission.
    //
    // NOTE: this gate is provisional. Whether source admission ultimately lives
    // on the bus or in a dedicated policy/source-registration issue is not yet
    // settled, so this set is intended to be overridden or reworked later.
    private static let productionSources: Set<CommandSource> = [
        .dashboard, .hotkey, .cli, .automation, .system,
    ]

    private struct Pending {
        var machine: CommandLifecycleMachine
        let envelope: CommandEnvelope
    }

    private let lock = NSLock()
    private let factory: CommandFactory
    private let executor: any CommandExecutor

    private var machines: [String: CommandLifecycleMachine] = [:]
    private var pending: [String: Pending] = [:]
    private var listeners: [Int: EventListener] = [:]
    private var nextToken = 0

    public init(factory: CommandFactory, executor: any CommandExecutor = StubCommandExecutor()) {
        self.factory = factory
        self.executor = executor
    }

    // MARK: - Subscriptions

    @discardableResult
    public func subscribe(_ listener: @escaping EventListener) -> CommandBusSubscription {
        lock.lock()
        defer { lock.unlock() }
        let token = nextToken
        nextToken += 1
        listeners[token] = listener
        return CommandBusSubscription(token: token)
    }

    public func unsubscribe(_ subscription: CommandBusSubscription) {
        lock.lock()
        defer { lock.unlock() }
        listeners[subscription.token] = nil
    }

    // MARK: - Submission

    /// Submits a command. Reserved sources are rejected before any state or
    /// event is created.
    @discardableResult
    public func submit(_ envelope: CommandEnvelope) throws -> CommandReceipt {
        guard Self.productionSources.contains(envelope.source) else {
            throw SubmissionError.reservedSource(envelope.source)
        }

        lock.lock()
        var machine = CommandLifecycleMachine(commandId: envelope.id, factory: factory)
        applyOrIgnore { try machine.markReceived(message: "Command received.") }
        applyOrIgnore { try machine.markPlanned(message: "Command planned.") }

        if executor.requiresConfirmation(envelope) {
            applyOrIgnore { try machine.requireConfirmation(message: "Awaiting confirmation.") }
            pending[envelope.id] = Pending(machine: machine, envelope: envelope)
        } else {
            runToTerminal(&machine, envelope: envelope)
        }
        machines[envelope.id] = machine

        let receipt = CommandReceipt(commandId: envelope.id, status: machine.status ?? .received)
        let batch = machine.events
        let snapshot = Array(listeners.values)
        lock.unlock()

        publish(batch, to: snapshot)
        return receipt
    }

    /// Resolves a command awaiting confirmation. Approval runs it to a terminal
    /// state; denial ends it as `cancelled` (ADR-002). Returns `nil` if no such
    /// command is pending.
    @discardableResult
    public func decideConfirmation(commandId: String, approved: Bool) -> CommandReceipt? {
        lock.lock()
        guard var entry = pending[commandId] else {
            lock.unlock()
            return nil
        }
        let start = entry.machine.events.count
        if approved {
            runToTerminal(&entry.machine, envelope: entry.envelope)
        } else {
            applyOrIgnore { try entry.machine.denyConfirmation() }
        }
        pending[commandId] = nil
        machines[commandId] = entry.machine

        let receipt = CommandReceipt(commandId: commandId, status: entry.machine.status ?? .requiresConfirmation)
        let batch = Array(entry.machine.events[start...])
        let snapshot = Array(listeners.values)
        lock.unlock()

        publish(batch, to: snapshot)
        return receipt
    }

    /// Cancels a command. Idempotent: cancelling an already-terminal command
    /// emits no new event and never reports success. Returns the current
    /// receipt, or `nil` if the command is unknown.
    @discardableResult
    public func cancel(commandId: String) -> CommandReceipt? {
        lock.lock()

        if let machine = machines[commandId], machine.isTerminal {
            let receipt = CommandReceipt(commandId: commandId, status: machine.status ?? .cancelled)
            lock.unlock()
            return receipt
        }

        guard var entry = pending[commandId] else {
            lock.unlock()
            return nil
        }
        let start = entry.machine.events.count
        applyOrIgnore { try entry.machine.cancel(message: "Command cancelled.") }
        pending[commandId] = nil
        machines[commandId] = entry.machine

        let receipt = CommandReceipt(commandId: commandId, status: entry.machine.status ?? .cancelled)
        let batch = Array(entry.machine.events[start...])
        let snapshot = Array(listeners.values)
        lock.unlock()

        publish(batch, to: snapshot)
        return receipt
    }

    // MARK: - Queries

    public func status(of commandId: String) -> CommandStatus? {
        lock.lock()
        defer { lock.unlock() }
        return machines[commandId]?.status
    }

    public func events(of commandId: String) -> [CommandLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return machines[commandId]?.events ?? []
    }

    // MARK: - Internals

    /// Drives a non-terminal machine through running to a terminal state. The
    /// transitions are valid by construction, so any thrown error is an internal
    /// invariant violation and is ignored rather than surfaced as a command
    /// failure.
    private func runToTerminal(_ machine: inout CommandLifecycleMachine, envelope: CommandEnvelope) {
        applyOrIgnore { try machine.markRunning(message: "Running.") }
        switch executor.execute(envelope) {
        case let .succeeded(summary):
            applyOrIgnore { try machine.markSucceeded(message: summary) }
        case let .failed(code, message, category):
            applyOrIgnore {
                try machine.markFailed(error: lifecycleError(category: category, code: code, message: message), message: message)
            }
        case let .unavailable(summary):
            applyOrIgnore {
                try machine.markFailed(
                    error: lifecycleError(category: .unavailableCapability, code: "tool.unavailable", message: summary),
                    message: summary
                )
            }
        }
    }

    private func lifecycleError(category: CerebralContracts.Category, code: String, message: String) -> CerebralHelmCommandLifecycleEventError {
        CerebralHelmCommandLifecycleEventError(
            category: category,
            code: code,
            details: nil,
            message: message,
            remediation: nil
        )
    }

    private func applyOrIgnore(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            // Transitions issued here are valid by construction; a throw would be
            // an internal invariant violation, not a command-level failure.
        }
    }

    private func publish(_ events: [CommandLifecycleEvent], to listeners: [EventListener]) {
        for event in events {
            for listener in listeners {
                do {
                    try listener(event)
                } catch {
                    // Isolate subscriber failure: other subscribers and command
                    // state are unaffected.
                }
            }
        }
    }
}
