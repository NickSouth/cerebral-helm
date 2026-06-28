import Foundation
import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralShared
import CerebralStorage
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
    // SQLite is the single source of truth for operational history (ADR-006). One
    // migrated connection backs confirmations, commands, events, tool calls, and
    // note metadata; the NDJSON/file/mock adapters are demoted to test bindings.
    let database = try operationalDatabase(paths)
    let commands = CommandRepository(database: database)
    let toolCalls = ToolCallRepository(database: database)

    // Durable knowledge: notes are Markdown under the env-aware knowledge root,
    // with rebuildable metadata in SQLite. Composed here so CerebralTools never
    // depends on the knowledge package (the service is injected).
    let knowledge = MarkdownKnowledgeService(
        rootURL: paths.knowledgeRoot,
        metadataStore: SQLiteNoteMetadataStore(database: database),
        searchIndex: SQLiteNoteSearchIndex(database: database)
    )
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: paths.toolDescriptorsDirectory,
        knowledge: knowledge,
        hookCatalog: hookCatalog,
        modePlanner: modePlanner
    )

    return CommandRuntime(
        registry: registry,
        coordinator: ConfirmationCoordinator(store: SQLiteConfirmationStore(database: database)),
        factory: CommandFactory(clock: SystemClock(), identifiers: UUIDIdentifierGenerator()),
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: modePlanner,
        commandSink: { persistCommand($0, into: commands) },
        sink: { persistEvent($0, into: commands) },
        // Already redacted by the runtime; linked to its command by the runtime.
        toolCallSink: { commandID, data in persistToolCall(commandID, data, into: toolCalls) }
    )
}

/// Opens and migrates the operational SQLite database (ADR-006). This is where the
/// schema migrations run live; the database and migrator are idempotent, so every
/// invocation is a cheap no-op once the schema is current.
func operationalDatabase(_ paths: WorkspacePaths) throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .file(paths.operationalDatabasePath))
    try SchemaMigrator().migrate(database)
    return database
}

/// Builds the durable knowledge service over the env-aware knowledge root and the
/// operational database. Used by the `knowledge rebuild` surface, which needs the
/// concrete service to reconstruct its search index.
func makeKnowledgeService(_ paths: WorkspacePaths) throws -> MarkdownKnowledgeService {
    let database = try operationalDatabase(paths)
    return MarkdownKnowledgeService(
        rootURL: paths.knowledgeRoot,
        metadataStore: SQLiteNoteMetadataStore(database: database),
        searchIndex: SQLiteNoteSearchIndex(database: database)
    )
}

/// Reconstructs a command's latest status from the operational database — the
/// SQLite single source of truth that `command status` and `cancel` read (ADR-006).
func latestCommandStatus(id: String, options: GlobalOptions) throws -> CommandStatusRecord? {
    let paths = try workspacePaths(options)
    let repository = CommandRepository(database: try operationalDatabase(paths))
    let eventLines = try repository.events(commandID: id).compactMap(\.payload)
    return CommandStatusReader.latest(commandId: id, eventLines: eventLines)
}

/// The most recent event payloads from the operational database, oldest first —
/// the SQLite-sourced event stream `events tail` renders (ADR-006).
func recentEventPayloads(options: GlobalOptions, limit: Int) throws -> [String] {
    let paths = try workspacePaths(options)
    let repository = CommandRepository(database: try operationalDatabase(paths))
    return try repository.recentEventPayloads(limit: limit)
}

/// Writes the command row from its envelope before any event references it (FK
/// ordering). The raw command text is deliberately not persisted — it can contain
/// secrets (the NIC-34 leak class); only non-sensitive envelope metadata is stored.
private func persistCommand(_ envelope: CommandEnvelope, into repository: CommandRepository) {
    let record = CommandRecord(
        id: envelope.id,
        source: envelope.source.rawValue,
        redactedInput: nil,
        sensitivity: envelope.privacy.sensitivity.rawValue,
        cloudPolicy: envelope.privacy.cloudPolicy.rawValue,
        status: CommandStatus.received.rawValue,
        createdAt: envelope.timestamp,
        updatedAt: envelope.timestamp
    )
    try? repository.upsert(record)
}

/// Advances the command's status and records the event atomically, storing the
/// full event JSON as the row payload so readers reconstruct it verbatim.
private func persistEvent(_ event: CommandLifecycleEvent, into repository: CommandRepository) {
    let payload = (try? CommandCoding.makeEncoder().encode(event)).map { String(decoding: $0, as: UTF8.self) }
    let record = CommandEventRecord(
        id: event.id,
        commandID: event.commandID,
        status: event.currentStatus.rawValue,
        previousStatus: event.previousStatus?.rawValue,
        occurredAt: event.timestamp,
        payload: payload
    )
    try? repository.recordEvent(record)
}

/// Persists the already-redacted tool-call record (NIC-34), linked to its command.
private func persistToolCall(_ commandID: String, _ data: Data, into repository: ToolCallRepository) {
    guard let result = try? CerebralHelmToolResult(data: data) else { return }
    let record = ToolCallRecord(
        commandID: commandID,
        toolID: result.toolID,
        toolVersion: result.toolVersion,
        adapterID: result.adapterID,
        status: result.status.rawValue,
        durationMs: result.durationMS,
        startedAt: result.startedAt,
        completedAt: result.completedAt,
        redactedInput: encodeJSONObject(result.redactedInput),
        redactedOutput: encodeJSONObject(result.redactedOutput),
        errorCategory: result.error?.category.rawValue,
        errorCode: result.error?.code,
        errorMessage: result.error?.message
    )
    try? repository.record(record)
}

/// Serializes a JSON object to a compact string for a TEXT column.
private func encodeJSONObject(_ object: [String: JSONAny]) -> String? {
    guard let data = try? JSONEncoder().encode(object) else { return nil }
    return String(decoding: data, as: UTF8.self)
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

/// The active mode/context store, backed by the operational database (ADR-006).
private func makeModeStateStore(_ paths: WorkspacePaths) throws -> SQLiteModeStateStore {
    SQLiteModeStateStore(database: try operationalDatabase(paths))
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
    let database = try operationalDatabase(paths)
    let stateStore = SQLiteModeStateStore(database: database)
    let coordinator = ModeSessionCoordinator(
        stateStore: stateStore,
        sessionLog: SQLiteModeSessionLog(database: database)
    )

    let sessionResult: ModeSessionResult = (applyOutput.status == .success) ? .success : .partialSuccess
    // Carry the separately-managed context forward into the session record.
    let context = (try? stateStore.loadActiveContext()) ?? nil
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
    let store = try makeModeStateStore(paths)
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
