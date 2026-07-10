import Foundation
import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralRuntimeHost
import CerebralShared
import CerebralStorage
import CerebralTools

/// App-layer composition for the CLI: resolves the workspace paths for the given
/// options and delegates to the shared ``CerebralRuntimeHost`` composition, so the
/// CLI and the macOS shell build the identical live runtime (NIC-74b). The reusable
/// wiring — the registry, knowledge service, persistence sinks, and
/// `operationalDatabase` — now lives in `CerebralRuntimeHost`.
func makeCommandRuntime(_ options: GlobalOptions) throws -> CommandRuntime {
    try makeCommandRuntime(paths: workspacePaths(options))
}

/// Builds the backup service over the durable user state under the state root
/// (operational database, user configuration, knowledge manifest).
func makeBackupService(_ paths: WorkspacePaths) -> BackupService {
    // Back up the same knowledge root the runtime writes to — the user's re-pointed
    // location when set, else the env default (NIC-138), so backups never miss the
    // live knowledge folder.
    let stored = try? SQLiteSettingsStore(database: operationalDatabase(paths)).load()
    let knowledgeRoot = EffectiveSettings.knowledgeRootURL(
        reference: stored?.knowledgeRootReference, default: paths.knowledgeRoot
    )
    return BackupService(
        databasePath: paths.operationalDatabasePath,
        configFiles: [paths.activeConfigPath, paths.settingsMetadataPath],
        overridesDirectory: paths.overridesDirectory,
        knowledgeRoot: knowledgeRoot
    )
}

/// Builds the durable knowledge service over the env-aware knowledge root and the
/// operational database. Used by the `knowledge rebuild` surface, which needs the
/// concrete service to reconstruct its search index.
func makeKnowledgeService(_ paths: WorkspacePaths) throws -> MarkdownKnowledgeService {
    let database = try operationalDatabase(paths)
    let stored = try? SQLiteSettingsStore(database: database).load()
    let root = EffectiveSettings.knowledgeRootURL(
        reference: stored?.knowledgeRootReference, default: paths.knowledgeRoot
    )
    return MarkdownKnowledgeService(
        rootURL: root,
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
// The active mode/context store comes from the shared runtime-host composition
// (`makeModeStateStore`), backed by the operational database (ADR-006).

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
