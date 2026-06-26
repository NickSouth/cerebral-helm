import CerebralContracts

/// The terminal outcome an executor produces for a command.
///
/// The command lifecycle has only three terminal states; `unavailable` maps to
/// a `failed` event carrying the `unavailable_capability` error category so the
/// pre-Mac foundation reports honest structured failures rather than false
/// success (PRD §4.6, §8.2).
public enum CommandOutcome {
    case succeeded(summary: String)
    case failed(code: String, message: String, category: Category)
    case unavailable(summary: String)
}

/// Minimal execution boundary the bus dispatches to.
///
/// NIC-25 ships only a stub; the real policy engine, tool registry, and native
/// adapters live in later issues. This boundary lets the bus drive the full
/// lifecycle (including the confirmation branch) deterministically today.
public protocol CommandExecutor: Sendable {
    /// Whether the command must pause for confirmation before running.
    func requiresConfirmation(_ envelope: CommandEnvelope) -> Bool
    /// Produces the command's terminal outcome.
    func execute(_ envelope: CommandEnvelope) -> CommandOutcome
}

/// Default pre-Mac executor: no tool adapter exists yet, so every command
/// resolves to a structured `unavailable` failure without requiring confirmation.
public struct StubCommandExecutor: CommandExecutor {
    public init() {}

    public func requiresConfirmation(_ envelope: CommandEnvelope) -> Bool { false }

    public func execute(_ envelope: CommandEnvelope) -> CommandOutcome {
        .unavailable(summary: "No executable adapter is available in the pre-Mac foundation.")
    }
}
