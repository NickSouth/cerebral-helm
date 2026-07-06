import Foundation
import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralShared
import CerebralStorage
import CerebralTools

/// Portable app-layer composition: builds the live ``CommandRuntime`` by wiring the
/// validated registry, portable handlers, mock native adapters, durable knowledge
/// service, policy engine, and confirmation coordinator against a resolved
/// ``WorkspacePaths``. This is the single place that imports both the core and the
/// tools/knowledge/storage packages, shared by every app-layer host (the `cerebral`
/// CLI and the macOS shell) so the runtime is composed once, not per surface.
///
/// It contains no AppKit and no CLI argument handling — callers resolve their own
/// ``WorkspacePaths`` and pass it in.
///
/// `onEvent`, when supplied, is invoked for every command lifecycle event *in
/// addition to* persistence — the macOS bridge uses it to forward the event stream
/// to the dashboard (NIC-74b). The CLI omits it.
///
/// `phase` selects which descriptor availability flag gates execution and
/// planning (``ExecutionPhase``). The default `.preMac` keeps the CLI on the
/// portable mock surface; the macOS shell composes with `.macOS`.
public func makeCommandRuntime(
    paths: WorkspacePaths,
    phase: ExecutionPhase = .preMac,
    onEvent: (@Sendable (CommandLifecycleEvent) -> Void)? = nil
) throws -> CommandRuntime {
    let references = try ReferenceCatalogLoader.load(configDirectory: paths.configDirectory)
    let hookCatalog = makeHookCatalog(references: references, repositoryRoot: paths.repositoryRoot)
    let modePlanner = try PreMacToolRuntime.makeActionPlanner(
        descriptorsDirectory: paths.toolDescriptorsDirectory,
        configDirectory: paths.configDirectory,
        phase: phase
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
        phase: phase,
        coordinator: ConfirmationCoordinator(store: SQLiteConfirmationStore(database: database)),
        factory: CommandFactory(clock: SystemClock(), identifiers: UUIDIdentifierGenerator()),
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: modePlanner,
        commandSink: { persistCommand($0, into: commands) },
        sink: { event in
            persistEvent(event, into: commands)
            onEvent?(event)
        },
        // Already redacted by the runtime; linked to its command by the runtime.
        toolCallSink: { commandID, data in persistToolCall(commandID, data, into: toolCalls) }
    )
}

/// Opens and migrates the operational SQLite database (ADR-006). The database and
/// migrator are idempotent, so every invocation is a cheap no-op once current.
public func operationalDatabase(_ paths: WorkspacePaths) throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .file(paths.operationalDatabasePath))
    try SchemaMigrator().migrate(database)
    return database
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
