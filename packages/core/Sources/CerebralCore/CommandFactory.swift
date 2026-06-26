import CerebralContracts
import CerebralShared

/// Builds command-spine values with injectable time and identifiers.
///
/// Centralizing construction here is what makes the lifecycle deterministic
/// under fixed fixtures and clocks (PRD NFR-04): every identifier and timestamp
/// flows from the injected ``TimeSource`` and ``IdentifierGenerator``. The
/// factory constructs values only; it does not decide lifecycle transitions or
/// policy, which belong to later increments.
public struct CommandFactory: Sendable {
    public let clock: any TimeSource
    public let identifiers: any IdentifierGenerator
    public let schemaVersion: String

    public init(
        clock: any TimeSource,
        identifiers: any IdentifierGenerator,
        schemaVersion: String = CommandContract.schemaVersion
    ) {
        self.clock = clock
        self.identifiers = identifiers
        self.schemaVersion = schemaVersion
    }

    /// Builds a versioned command envelope. The identifier and timestamp are
    /// minted from the injected dependencies; callers supply intent.
    public func makeEnvelope(
        source: CommandSource,
        rawInput: String,
        payload: [String: JSONAny] = [:],
        privacy: CommandPrivacy,
        correlationId: String? = nil
    ) -> CommandEnvelope {
        CommandEnvelope(
            correlationID: correlationId,
            id: identifiers.nextIdentifier(for: .command),
            payload: payload,
            privacy: privacy,
            rawInput: rawInput,
            schemaVersion: schemaVersion,
            source: source,
            timestamp: clock.now(),
            type: .commandSubmit
        )
    }

    /// Builds a single immutable lifecycle transition event. This constructs an
    /// event value only; transition legality is enforced by the lifecycle state
    /// machine in a later increment.
    public func makeLifecycleEvent(
        commandId: String,
        previousStatus: CommandStatus?,
        currentStatus: CommandStatus,
        message: String? = nil,
        error: CerebralHelmCommandLifecycleEventError? = nil
    ) -> CommandLifecycleEvent {
        CommandLifecycleEvent(
            commandID: commandId,
            currentStatus: currentStatus,
            error: error,
            id: identifiers.nextIdentifier(for: .event),
            message: message,
            previousStatus: previousStatus,
            schemaVersion: schemaVersion,
            timestamp: clock.now(),
            type: .commandLifecycleTransition
        )
    }

    /// Builds a structured terminal result for a completed command.
    public func makeTerminalResult(
        commandId: String,
        status: TerminalStatus,
        summary: String,
        output: [String: JSONAny] = [:],
        error: CerebralHelmCommandTerminalResultError? = nil
    ) -> CommandTerminalResult {
        CommandTerminalResult(
            commandID: commandId,
            completedAt: clock.now(),
            error: error,
            output: output,
            schemaVersion: schemaVersion,
            status: status,
            summary: summary
        )
    }
}
