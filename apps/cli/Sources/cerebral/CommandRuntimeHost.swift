import Foundation
import CerebralContracts
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
    let modePlanner = try PreMacToolRuntime.makeActionPlanner(
        descriptorsDirectory: paths.toolDescriptorsDirectory,
        configDirectory: paths.configDirectory
    )
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: paths.toolDescriptorsDirectory,
        knowledge: MockKnowledgeService(),
        hookCatalog: hookCatalog,
        modePlanner: modePlanner
    )
    let writer = EventLogWriter(eventLogPath: paths.eventLogPath)
    let toolCallLogPath = paths.eventLogPath.deletingLastPathComponent().appendingPathComponent("tool-calls.ndjson")

    return CommandRuntime(
        registry: registry,
        coordinator: ConfirmationCoordinator(),
        factory: CommandFactory(clock: SystemClock(), identifiers: UUIDIdentifierGenerator()),
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: modePlanner,
        sink: { try? writer.append($0) },
        // Already redacted by the runtime; append one JSON line per tool call.
        toolCallSink: { appendLine($0, to: toolCallLogPath) }
    )
}

/// Appends one NDJSON line to a development log, creating the directory as needed.
private func appendLine(_ data: Data, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
        try? Data().write(to: url)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    try? handle.seekToEnd()
    var line = data
    line.append(0x0A)
    try? handle.write(contentsOf: line)
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
/// approves it within the same invocation. Returns the terminal outcome so a
/// caller (e.g. `mode`) can record follow-up state.
@discardableResult
func runThroughRuntime(_ rawInput: String, options: GlobalOptions) async throws -> CommandRuntimeOutcome {
    let runtime = try makeCommandRuntime(options)
    var outcome = await runtime.submit(rawInput, source: .cli)

    if case let .awaitingConfirmation(_, _, token) = outcome, options.yes {
        outcome = await runtime.decide(token: token, decision: .approve)
    }

    print(options.json ? try RuntimeOutcomeRenderer.json(outcome) : RuntimeOutcomeRenderer.human(outcome))
    return outcome
}

// MARK: - Mode session state (NIC-39 / FR-MOD-05, FR-MOD-06)

private func makeModeStateStore(_ paths: WorkspacePaths) -> FileModeStateStore {
    FileModeStateStore(activeModePath: paths.activeModePath, activeContextPath: paths.activeContextPath)
}

/// Records a mode session and updates the active mode after a mode application
/// that actually executed. A confirmation that was not approved, a rejection, or
/// a denial produces no `mode.apply` output, so nothing is recorded — only a real
/// activation becomes history (FR-MOD-06) and the persisted active mode (FR-MOD-05).
func recordModeSessionIfApplied(modeID: String, outcome: CommandRuntimeOutcome, options: GlobalOptions) throws {
    guard
        case let .completed(_, _, result) = outcome,
        let result, result.toolID == "mode.apply",
        let output = result.output,
        let applyOutput = try? CerebralHelmModeApplyOutput(data: output)
    else { return }

    let paths = try workspacePaths(options)
    let store = makeModeStateStore(paths)
    let coordinator = ModeSessionCoordinator(
        stateStore: store,
        sessionLog: NDJSONModeSessionLog(path: paths.modeSessionLogPath)
    )

    let sessionResult: ModeSessionResult = (applyOutput.status == .success) ? .success : .partialSuccess
    // Carry the separately-managed context forward into the session record.
    let context = (try? store.loadActiveContext()) ?? nil
    try coordinator.recordApplication(
        modeID: modeID,
        context: context,
        source: "cli",
        result: sessionResult,
        configVersion: configVersion(paths: paths)
    )
}

/// Prints the restored active mode and context. The persisted mode is resolved
/// against the current config so a mode that no longer exists falls back to the
/// configured default rather than leaving the workspace stuck (FR-MOD-05).
func renderActiveMode(options: GlobalOptions) throws {
    let paths = try workspacePaths(options)
    let store = makeModeStateStore(paths)
    let persisted = (try? store.loadActiveModeID()) ?? nil
    let context = (try? store.loadActiveContext()) ?? nil

    var availableModeIDs: Set<String> = []
    var defaultModeID = persisted ?? ""
    if case let .valid(validated) = ConfigValidator.validate(configDirectory: paths.configDirectory) {
        availableModeIDs = Set(validated.modes.map(\.id))
        defaultModeID = validated.defaults.defaultModeID
    }

    let hasConfiguredDefault = !defaultModeID.isEmpty
    let active = hasConfiguredDefault
        ? ModeStateResolver.resolveActiveModeID(
            persisted: persisted, availableModeIDs: availableModeIDs, defaultModeID: defaultModeID
        )
        : persisted
    // "Fell back" means a previously-saved mode is no longer configured — not a
    // never-set state, which simply shows the default.
    let fellBack = persisted != nil && active != persisted

    if options.json {
        print(try ActiveModeRenderer.json(active: active, fellBack: fellBack, context: context))
    } else {
        print(ActiveModeRenderer.human(active: active, fellBack: fellBack, context: context))
    }
}

/// The active configuration version recorded with a session (the application
/// defaults' schema version; mirrors the future `settings_metadata` config version).
private func configVersion(paths: WorkspacePaths) -> String {
    guard case let .valid(validated) = ConfigValidator.validate(configDirectory: paths.configDirectory) else {
        return "unknown"
    }
    return validated.defaults.schemaVersion
}

/// Renders the active-mode read surface.
enum ActiveModeRenderer {
    private struct View: Codable {
        let activeMode: String?
        let restoredFromDefault: Bool
        let contextId: String?
        let contextLabel: String?
    }

    private static func view(_ active: String?, _ fellBack: Bool, _ context: ProjectContext?) -> View {
        View(activeMode: active, restoredFromDefault: fellBack, contextId: context?.id, contextLabel: context?.label)
    }

    static func json(active: String?, fellBack: Bool, context: ProjectContext?) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(view(active, fellBack, context)), as: UTF8.self)
    }

    static func human(active: String?, fellBack: Bool, context: ProjectContext?) -> String {
        guard let active else { return "No active mode yet. Apply one with: cerebral mode <id>" }
        var line = "Active mode: \(active)"
        if fellBack { line += " (restored to default; the saved mode is no longer configured)" }
        if let context { line += "\nActive context: \(context.label ?? context.id)" }
        return line
    }
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
