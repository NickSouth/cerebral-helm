import Foundation
import CerebralShared

/// The outcome of running one line of input through the session.
public enum RunOutcome: Equatable, Sendable {
    /// The input parsed and was submitted; the command reached `status`.
    case executed(commandId: String, status: CommandStatus, summary: String)
    /// The input did not resolve to a command and was not executed.
    case rejected(reason: String, suggestions: [String])
}

/// **Legacy / test-and-recovery only.** Composition root that wires the parser,
/// command factory, bus, and the NDJSON ``EventLogWriter`` together for a single
/// CLI invocation.
///
/// This is **not** part of the production write path. Per
/// [ADR-006](../../../../docs/adr/ADR-006-sqlite-single-source-of-truth.md),
/// SQLite (via `CerebralStorage`) is the single source of truth for operational
/// history; the NDJSON adapters this session wires up (``EventLogWriter`` plus
/// the `EventLogReader` / `CommandStatusReader` read surfaces) are demoted to
/// test/fixture and recovery bindings behind the Core ports — retained for
/// deterministic unit tests and fallback, never the runtime store.
///
/// The session loads reference catalogs from config, attaches an
/// ``EventLogWriter`` to the bus so lifecycle events persist, and exposes the
/// real command path used by the `mode`, `note`, and `search` surfaces. Clock,
/// identifiers, and executor are injectable for deterministic tests.
public struct CerebralSession {
    public let references: CommandReferences
    public let eventLogPath: URL

    private let parser: DirectCommandParser
    private let factory: CommandFactory
    private let bus: CommandBus

    public init(
        paths: WorkspacePaths,
        clock: any TimeSource = SystemClock(),
        identifiers: any IdentifierGenerator = UUIDIdentifierGenerator(),
        executor: any CommandExecutor = StubCommandExecutor()
    ) throws {
        self.references = try ReferenceCatalogLoader.load(configDirectory: paths.configDirectory)
        self.eventLogPath = paths.eventLogPath
        self.parser = DirectCommandParser(references: references)
        self.factory = CommandFactory(clock: clock, identifiers: identifiers)
        self.bus = CommandBus(factory: factory, executor: executor)

        let writer = EventLogWriter(eventLogPath: paths.eventLogPath)
        bus.subscribe { try writer.append($0) }
    }

    /// Parses `rawInput` and, if it resolves to an intent, submits it through
    /// the bus. Unrecognized or ambiguous input is reported without executing.
    public func run(_ rawInput: String, source: CommandSource) throws -> RunOutcome {
        switch parser.parse(rawInput) {
        case .parsed:
            let envelope = factory.makeEnvelope(
                source: source,
                rawInput: rawInput,
                privacy: CommandPrivacy(cloudPolicy: .deny, sensitivity: .sensitivityPrivate)
            )
            let receipt = try bus.submit(envelope)
            let summary = bus.events(of: receipt.commandId).last?.message ?? ""
            return .executed(commandId: receipt.commandId, status: receipt.status, summary: summary)

        case let .unrecognized(unrecognized):
            return .rejected(reason: Self.describe(unrecognized.reason), suggestions: unrecognized.suggestions)

        case let .ambiguous(ambiguous):
            return .rejected(
                reason: "Ambiguous reference '\(ambiguous.token)' for '\(ambiguous.verb)'.",
                suggestions: ambiguous.candidates.map { "\($0.kind):\($0.id)" }
            )
        }
    }

    /// The latest persisted status for a command, or `nil` if unknown.
    public func status(of commandId: String) throws -> CommandStatusRecord? {
        try CommandStatusReader.latest(commandId: commandId, eventLogPath: eventLogPath)
    }

    private static func describe(_ reason: UnrecognizedInput.Reason) -> String {
        switch reason {
        case .emptyInput:
            return "No command entered."
        case let .unknownVerb(verb):
            return "Unknown command '\(verb)'."
        case let .missingArgument(verb):
            return "Missing argument for '\(verb)'."
        case let .unresolvedReference(verb, token):
            return "Unknown \(verb) reference '\(token)'."
        }
    }
}
