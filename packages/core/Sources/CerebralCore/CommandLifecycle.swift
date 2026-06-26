import CerebralContracts

/// The command lifecycle rules.
///
/// The allowed transitions mirror exactly the `oneOf` in
/// `packages/contracts/schemas/commands/command-lifecycle-event.schema.json`
/// and ADR-002. `received`, `planned`, `requires_confirmation`, and `running`
/// are non-terminal; `succeeded`, `failed`, and `cancelled` are terminal and
/// immutable. A `nil` previous status represents a command that has not yet
/// entered the lifecycle.
public enum CommandLifecycle {
    /// All non-`nil` statuses.
    public static let allStatuses: [CommandStatus] = [
        .received, .planned, .requiresConfirmation, .running,
        .succeeded, .failed, .cancelled,
    ]

    /// `true` when `status` is terminal and admits no further transition.
    public static func isTerminal(_ status: CommandStatus) -> Bool {
        switch status {
        case .succeeded, .failed, .cancelled:
            return true
        case .received, .planned, .requiresConfirmation, .running:
            return false
        }
    }

    /// `true` when moving from `previous` to `next` is a legal transition.
    ///
    /// A `nil` `previous` is only valid when entering at `received`.
    public static func isValidTransition(from previous: CommandStatus?, to next: CommandStatus) -> Bool {
        switch (previous, next) {
        case (.none, .received),
             (.received, .planned),
             (.planned, .requiresConfirmation),
             (.planned, .running),
             (.requiresConfirmation, .running),
             (.requiresConfirmation, .cancelled),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .cancelled):
            return true
        default:
            return false
        }
    }
}

/// A deterministic failure raised when a lifecycle transition is rejected.
///
/// Invalid transitions never mutate command state and never emit a lifecycle
/// event (the event schema only admits valid transitions). The bus may turn
/// ``structuredError`` into an internal diagnostic event (ADR-002).
public enum LifecycleTransitionError: Error, Equatable {
    /// The requested transition is not a legal edge.
    case invalidTransition(from: CommandStatus?, to: CommandStatus)
    /// The command is already terminal and cannot transition again.
    case terminalCommand(status: CommandStatus, attempted: CommandStatus)

    /// A contract-shaped error describing this rejection.
    public var structuredError: StructuredError {
        switch self {
        case let .invalidTransition(from, to):
            return StructuredError(
                category: .invalidTransition,
                code: "lifecycle.invalid_transition",
                details: nil,
                message: "Invalid lifecycle transition from \(from?.rawValue ?? "none") to \(to.rawValue).",
                remediation: nil
            )
        case let .terminalCommand(status, attempted):
            return StructuredError(
                category: .invalidTransition,
                code: "lifecycle.terminal_immutable",
                details: nil,
                message: "Command is already terminal (\(status.rawValue)); cannot transition to \(attempted.rawValue).",
                remediation: nil
            )
        }
    }
}
