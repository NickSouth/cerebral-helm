import CerebralContracts

/// Drives a single command through the lifecycle, enforcing legal transitions
/// and terminal immutability while recording an ordered, append-only log of
/// immutable lifecycle events.
///
/// The machine constructs events through ``CommandFactory``, so identifiers and
/// timestamps come from the injected clock and identifier generator and are
/// deterministic under fixtures (PRD NFR-04). Multi-subscriber fan-out of these
/// events is the command bus's responsibility (NIC-25); this type owns the
/// per-command transition rules and the ordered record.
public struct CommandLifecycleMachine {
    public let commandId: String
    private let factory: CommandFactory

    /// The current status, or `nil` before the command is received.
    public private(set) var status: CommandStatus?

    /// The ordered, append-only log of emitted transition events.
    public private(set) var events: [CommandLifecycleEvent]

    public init(commandId: String, factory: CommandFactory) {
        self.commandId = commandId
        self.factory = factory
        self.status = nil
        self.events = []
    }

    /// `true` once the command has reached a terminal status.
    public var isTerminal: Bool {
        guard let status else { return false }
        return CommandLifecycle.isTerminal(status)
    }

    /// Applies a transition to `next`, emitting and recording one immutable
    /// event on success.
    ///
    /// - Throws: ``LifecycleTransitionError/terminalCommand(status:attempted:)``
    ///   if the command is already terminal, or
    ///   ``LifecycleTransitionError/invalidTransition(from:to:)`` if the edge is
    ///   illegal. In both cases state is left unchanged and no event is emitted.
    @discardableResult
    public mutating func transition(
        to next: CommandStatus,
        message: String? = nil,
        error: CerebralHelmCommandLifecycleEventError? = nil
    ) throws -> CommandLifecycleEvent {
        if let status, CommandLifecycle.isTerminal(status) {
            throw LifecycleTransitionError.terminalCommand(status: status, attempted: next)
        }
        guard CommandLifecycle.isValidTransition(from: status, to: next) else {
            throw LifecycleTransitionError.invalidTransition(from: status, to: next)
        }

        let event = factory.makeLifecycleEvent(
            commandId: commandId,
            previousStatus: status,
            currentStatus: next,
            message: message,
            error: error
        )
        status = next
        events.append(event)
        return event
    }
}

// Intent-revealing transition helpers. Each delegates to `transition(to:…)`, so
// transition legality and terminal immutability remain centrally enforced.
public extension CommandLifecycleMachine {
    @discardableResult
    mutating func markReceived(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .received, message: message)
    }

    @discardableResult
    mutating func markPlanned(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .planned, message: message)
    }

    @discardableResult
    mutating func requireConfirmation(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .requiresConfirmation, message: message)
    }

    @discardableResult
    mutating func markRunning(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .running, message: message)
    }

    @discardableResult
    mutating func markSucceeded(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .succeeded, message: message)
    }

    @discardableResult
    mutating func markFailed(
        error: CerebralHelmCommandLifecycleEventError,
        message: String? = nil
    ) throws -> CommandLifecycleEvent {
        try transition(to: .failed, message: message, error: error)
    }

    @discardableResult
    mutating func cancel(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .cancelled, message: message)
    }

    /// Records a denied confirmation. Per ADR-002 a denied confirmation ends as
    /// `cancelled`, not `failed`; the transition rules only allow this from
    /// `requires_confirmation`.
    @discardableResult
    mutating func denyConfirmation(message: String? = nil) throws -> CommandLifecycleEvent {
        try transition(to: .cancelled, message: message ?? "Confirmation denied.")
    }
}
