import Foundation
import CerebralCore
import CerebralShared
import CerebralTools

/// App-layer composition: builds the live ``CommandRuntime`` by wiring the
/// validated registry, portable handlers, mock native adapters, mock knowledge
/// service, policy engine, and confirmation coordinator against the repository
/// config and development state roots. This is the only place that imports both
/// the core and the tools package.
func makeCommandRuntime(_ options: GlobalOptions) throws -> CommandRuntime {
    let paths = try workspacePaths(options)
    let references = try ReferenceCatalogLoader.load(configDirectory: paths.configDirectory)
    let hookCatalog = makeHookCatalog(references: references, repositoryRoot: paths.repositoryRoot)
    let modePlanner = StubModePlanner()
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: paths.toolDescriptorsDirectory,
        knowledge: MockKnowledgeService(),
        hookCatalog: hookCatalog,
        modePlanner: modePlanner
    )
    let writer = EventLogWriter(eventLogPath: paths.eventLogPath)

    return CommandRuntime(
        registry: registry,
        coordinator: ConfirmationCoordinator(),
        factory: CommandFactory(clock: SystemClock(), identifiers: UUIDIdentifierGenerator()),
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: modePlanner,
        sink: { try? writer.append($0) }
    )
}

/// Resolves each configured hook reference to an exact invocation. The pre-Mac
/// mock process adapter never runs it, but the exact-match policy needs a fully
/// specified invocation (FR-SAF-03).
private func makeHookCatalog(references: CommandReferences, repositoryRoot: URL) -> HookCatalog {
    var invocations: [String: HookInvocation] = [:]
    for (id, reference) in references.hooks {
        invocations[id] = HookInvocation(
            executable: reference.target,
            arguments: [],
            workingDirectory: repositoryRoot.path,
            environment: [:]
        )
    }
    return HookCatalog(invocations)
}

/// Parses and runs one line of input through the runtime, printing the outcome.
/// A confirmation-required command stops with its disclosure unless `--yes`
/// approves it within the same invocation.
func runThroughRuntime(_ rawInput: String, options: GlobalOptions) async throws {
    let runtime = try makeCommandRuntime(options)
    var outcome = await runtime.submit(rawInput, source: .cli)

    if case let .awaitingConfirmation(_, _, token) = outcome, options.yes {
        outcome = await runtime.decide(token: token, decision: .approve)
    }

    print(options.json ? try RuntimeOutcomeRenderer.json(outcome) : RuntimeOutcomeRenderer.human(outcome))
}

/// Renders a ``CommandRuntimeOutcome`` in human- and machine-readable forms.
enum RuntimeOutcomeRenderer {
    private struct Summary: Codable {
        let kind: String
        var commandId: String?
        var status: String?
        var toolId: String?
        var toolStatus: String?
        var errorCategory: String?
        var message: String?
        var actionSummary: String?
        var risk: String?
        var requiresConfirmation: Bool?
        var reason: String?
        var suggestions: [String]?
    }

    private static func summary(_ outcome: CommandRuntimeOutcome) -> Summary {
        switch outcome {
        case let .completed(commandID, status, result):
            return Summary(
                kind: "completed",
                commandId: commandID,
                status: status.rawValue,
                toolId: result?.toolID,
                toolStatus: result?.status.rawValue,
                errorCategory: result?.error?.category.rawValue,
                message: result?.error?.message
            )
        case let .awaitingConfirmation(commandID, disclosure, _):
            return Summary(
                kind: "awaiting_confirmation",
                commandId: commandID,
                actionSummary: disclosure.actionSummary,
                risk: disclosure.risk.rawValue,
                requiresConfirmation: true
            )
        case let .rejected(reason, suggestions):
            return Summary(kind: "rejected", reason: reason, suggestions: suggestions)
        }
    }

    static func json(_ outcome: CommandRuntimeOutcome) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(summary(outcome)), as: UTF8.self)
    }

    static func human(_ outcome: CommandRuntimeOutcome) -> String {
        switch outcome {
        case let .completed(commandID, status, result):
            var line = "Command \(commandID): \(status.rawValue)."
            if let result {
                line += " Tool \(result.toolID): \(result.status.rawValue)."
                if let error = result.error {
                    line += " (\(error.category.rawValue): \(error.message))"
                }
            }
            return line
        case let .awaitingConfirmation(commandID, disclosure, _):
            return """
            Command \(commandID) requires confirmation [\(disclosure.risk.rawValue)]: \(disclosure.actionSummary)
            Execution has not happened yet. Re-run with --yes to approve.
            """
        case let .rejected(reason, suggestions):
            let hint = suggestions.isEmpty ? "" : "\nTry: \(suggestions.joined(separator: ", "))"
            return "Rejected: \(reason)\(hint)"
        }
    }
}
