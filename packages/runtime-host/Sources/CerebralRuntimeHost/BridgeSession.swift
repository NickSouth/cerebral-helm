import Foundation
import CerebralContracts
import CerebralCore

/// Executes versioned bridge operation requests against the live ``CommandRuntime``
/// (NIC-74b, ADR-004). Transport-agnostic: the WKWebView transport (or a test) hands
/// it a decoded operation request and forwards the response it returns.
///
/// This increment maps the command-style operations — `submitCommand` and
/// `applyMode` — onto `CommandRuntime.submit`. The structured knowledge/confirmation/
/// settings operations, `getBootstrapState`, `getRecentActivity`, and the event
/// stream land in following increments; until then they return a structured
/// `unavailable_capability` error so the dashboard degrades honestly rather than
/// hanging on a missing reply.
public final class BridgeSession: @unchecked Sendable {
    private let runtime: CommandRuntime
    private let configDirectory: URL
    /// Durable settings persistence (FR-CFG-04). Optional so a host without a
    /// database binding (some tests) still validates patches; when absent, an
    /// accepted patch is validated but not saved — the pre-store behavior.
    private let settingsStore: (any SettingsStore)?
    /// The durable active-mode store (FR-MOD-05). When bound, bootstrap restores
    /// the last active mode; when absent, the stored default applies.
    private let modeStateStore: (any ModeStateStore)?
    /// The composed capability flags the handshake reports (FR-SHL-06), derived at
    /// composition time from the bound capability bundle, phase, and platform
    /// permissions (``CompositionCapabilities``). Defaults to the honest pre-Mac
    /// mock set: every native capability unavailable. Mutable because permission
    /// state can change while running (NIC-83) — the shell rechecks on activation
    /// and updates via ``updateCapabilities(_:)``.
    public var capabilities: [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return currentCapabilities
    }

    private let capabilitiesLock = NSLock()
    private var currentCapabilities: [CerebralContracts.Capability]
    private let messageSchemaVersion = "1.0.0"
    /// Emits an already-encoded bridge-event JSON string to the dashboard (Sendable
    /// String — no non-Sendable DTO crosses the transport boundary).
    private let emitEventJSON: @Sendable (String) -> Void

    /// Pending confirmations awaiting a decision, keyed by disclosure id
    /// (== `ConfirmationToken.confirmationID`). The token is a single-use secret held
    /// only here; the dashboard decides by id and never sees the token.
    private let tokenLock = NSLock()
    private var pendingTokens: [String: ConfirmationToken] = [:]

    public init(
        runtime: CommandRuntime,
        configDirectory: URL,
        capabilities: [CerebralContracts.Capability] = CompositionCapabilities.bridgeCapabilities(phase: .preMac, nativeCapabilityIDs: []),
        settingsStore: (any SettingsStore)? = nil,
        modeStateStore: (any ModeStateStore)? = nil,
        emitEventJSON: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.configDirectory = configDirectory
        self.settingsStore = settingsStore
        self.modeStateStore = modeStateStore
        self.currentCapabilities = capabilities
        self.emitEventJSON = emitEventJSON
    }

    /// Replaces the reported capability set (a permission recheck, NIC-83) and
    /// returns the capabilities whose availability changed, so the caller can
    /// emit one `bridge.capability.changed` event per transition. Future
    /// handshakes report the updated set.
    public func updateCapabilities(
        _ updated: [CerebralContracts.Capability]
    ) -> [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        let previousByID = Dictionary(uniqueKeysWithValues: currentCapabilities.map { ($0.id, $0) })
        currentCapabilities = updated
        return updated.filter { capability in
            previousByID[capability.id]?.available != capability.available
        }
    }

    public func execute(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        switch request.operation {
        case .getBootstrapState:
            return ok(request, payload: BootstrapComposer.compose(
                configDirectory: configDirectory, activeModeID: bootstrapModeID()
            ))
        case .submitCommand:
            return await submitCommand(request)
        case .applyMode:
            return await applyMode(request)
        case .captureNote:
            return await captureNote(request)
        case .searchNotes:
            return await searchNotes(request)
        case .getRecentActivity:
            return getRecentActivity(request)
        case .decideConfirmation:
            return await decideConfirmation(request)
        case .updateSettings:
            return updateSettings(request)
        default:
            // captureNote (confirmation-gated local_write returning a synchronous
            // noteId) and subscribe follow later.
            return unimplemented(request)
        }
    }

    // MARK: - Operations

    private func submitCommand(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SubmitCommandInput = decodePayload(request), !input.rawInput.isEmpty else {
            return invalidInput(request, "submitCommand requires a non-empty rawInput.")
        }
        // Honor an explicit, known source; default to `dashboard`. This keeps the
        // command bus honest about provenance (FR-CMD-01) without trusting arbitrary
        // strings.
        let source = input.source.flatMap(CommandSource.init(rawValue:)) ?? .dashboard
        let outcome = await runtime.submit(input.rawInput, source: source)
        registerAwaitingConfirmation(outcome)
        emitConfigChangedIfModeApplied(outcome)
        return ok(request, payload: receipt(for: outcome))
    }

    /// A raw `mode <id>` command (palette, CLI-over-bridge) that succeeded also
    /// re-themes the dashboard, exactly like the `applyMode` operation — one
    /// switch, one visible result, regardless of which surface asked.
    private func emitConfigChangedIfModeApplied(_ outcome: CommandRuntimeOutcome) {
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let result, result.toolID == "mode.apply",
            let output = result.output,
            let decoded = try? CerebralHelmModeApplyOutput(data: output)
        else { return }
        let snapshot = BootstrapComposer.compose(configDirectory: configDirectory, activeModeID: decoded.modeID)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func applyMode(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ApplyModeInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "applyMode requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "error"))
        }
        // A mode switch is a real command: `mode.apply` persists the active mode
        // and records a session (FR-MOD-05/06). It runs no workflow steps — the
        // dashboard swap below and the durable switch are the whole effect
        // (workspace re-scope, NIC-85).
        _ = await runtime.submit("mode \(input.modeId)", source: .dashboard)
        // Re-theme the dashboard by emitting the target mode's snapshot.
        let snapshot = BootstrapComposer.compose(configDirectory: configDirectory, activeModeID: input.modeId)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "ok"))
    }

    private func captureNote(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CaptureNoteInput = decodePayload(request), !input.title.isEmpty else {
            return invalidInput(request, "captureNote requires a title.")
        }
        // note.capture is a confirmation-gated local_write, so this enters the bus and
        // the disclosure is pushed to the UI. The note is written after the user
        // approves; the returned id is the command handle (see the captureNote contract
        // note — a synchronous noteId is not possible for a gated capture).
        let text = input.body.isEmpty ? input.title : "\(input.title)\n\(input.body)"
        let outcome = await runtime.submit("note \(text)", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        switch outcome {
        case let .completed(commandID, _, result):
            if let data = result?.output, let output = try? CerebralHelmNoteCaptureOutput(data: data) {
                return ok(request, payload: CaptureNoteResult(noteId: output.noteID))
            }
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case .rejected:
            return errorResponse(
                request, category: .invalidInput,
                code: "note_rejected", message: "The note could not be parsed."
            )
        }
    }

    private func searchNotes(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SearchNotesInput = decodePayload(request), !input.text.isEmpty else {
            // An empty query yields no results rather than an error (empty search box).
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let outcome = await runtime.submit("search \(input.text)", source: .dashboard)
        guard
            case let .completed(_, _, result) = outcome,
            let data = result?.output,
            let output = try? CerebralHelmNoteSearchOutput(data: data)
        else {
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let hits = output.results.map {
            NoteHit(noteId: $0.noteID, title: $0.title, excerpt: $0.excerpt)
        }
        return ok(request, payload: SearchNotesResult(results: hits))
    }

    /// The recent-activity read surface. A fresh session has no activity; the durable
    /// DB-backed history read is a follow-on increment, so this returns the honest
    /// empty envelope (the dashboard renders an empty feed rather than fabricated rows).
    private func getRecentActivity(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: RecentActivityEnvelope())
    }

    private func decideConfirmation(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: DecideConfirmationInput = decodePayload(request), !input.id.isEmpty else {
            return invalidInput(request, "decideConfirmation requires an id and decision.")
        }
        guard let token = takeToken(id: input.id) else {
            return errorResponse(
                request, category: .invalidInput,
                code: "unknown_confirmation", message: "No pending confirmation for \(input.id)."
            )
        }
        // Only approve/cancel cross the bridge; anything else fails closed as cancel.
        let decision: ConfirmationDecision = (input.decision == "approve") ? .approve : .cancel
        _ = await runtime.decide(token: token, decision: decision)
        // Clear the active confirmation in the UI; the command's own completion/cancel
        // is carried by the lifecycle event stream.
        emit(BridgeEventFactory.confirmationEvent(disclosure: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()))
        return ok(request, payload: DecideConfirmationResult(confirmationId: input.id, decision: input.decision))
    }

    /// Validates a settings patch against the deterministic allowlist (ADR-003) and
    /// persists an accepted patch through the settings store: unknown or
    /// policy-weakening keys are rejected before anything is saved, and a store
    /// failure is a structured error — `accepted` is never reported for a patch
    /// that did not become durable (FR-CFG-04).
    private func updateSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard
            let data = try? JSONEncoder().encode(request.payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let patch = object["patch"] as? [String: Any]
        else {
            return invalidInput(request, "updateSettings requires a patch.")
        }
        let changes = (patch["changes"] as? [String: Any]) ?? [:]
        let errors = SettingsPatchValidator.validate(changes: changes)
        guard errors.isEmpty else {
            return ok(request, payload: UpdateSettingsResult(accepted: false))
        }
        if let settingsStore {
            do {
                try settingsStore.apply(SettingsChanges(validatedChanges: changes))
            } catch {
                return errorResponse(
                    request, category: .internalFailure,
                    code: "settings_not_saved",
                    message: "The settings change could not be saved."
                )
            }
        }
        return ok(request, payload: UpdateSettingsResult(accepted: true))
    }

    /// The mode bootstrap should activate: the last active mode when it still
    /// exists in config (FR-MOD-05 restart restore), else the stored default
    /// mode, else `nil` for the configured default. Stale references fall back,
    /// never error.
    private func bootstrapModeID() -> String? {
        if let store = modeStateStore,
           let lastActive = try? store.loadActiveModeID(),
           BootstrapComposer.modeExists(lastActive, configDirectory: configDirectory) {
            return lastActive
        }
        guard
            let store = settingsStore,
            let settings = try? store.load(),
            let stored = settings.defaultModeID,
            BootstrapComposer.modeExists(stored, configDirectory: configDirectory)
        else { return nil }
        return stored
    }

    // MARK: - Confirmation flow

    /// When a command pauses for confirmation, remember its single-use token and push
    /// the policy-owned disclosure to the dashboard as a `confirmation.changed` event.
    private func registerAwaitingConfirmation(_ outcome: CommandRuntimeOutcome) {
        guard case let .awaitingConfirmation(_, disclosure, token) = outcome else { return }
        tokenLock.lock()
        pendingTokens[token.confirmationID] = token
        tokenLock.unlock()
        emit(BridgeEventFactory.confirmationEvent(
            disclosure: disclosure, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func takeToken(id: String) -> ConfirmationToken? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return pendingTokens.removeValue(forKey: id)
    }

    private func emit(_ event: CerebralHelmBridgeEvent) {
        guard let data = try? BridgeMessageCoding.encoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        emitEventJSON(json)
    }

    // MARK: - Payload mapping

    private struct SubmitCommandInput: Decodable {
        let rawInput: String
        let source: String?
    }
    private struct CommandReceipt: Encodable {
        let commandId: String
        let accepted: Bool
    }
    private struct ApplyModeInput: Decodable {
        let modeId: String
    }
    private struct ApplyModeResult: Encodable {
        let modeId: String
        let status: String
    }
    private struct CaptureNoteInput: Decodable {
        let title: String
        let body: String
        let kind: String?
    }
    private struct CaptureNoteResult: Encodable {
        let noteId: String
    }
    private struct SearchNotesInput: Decodable {
        let text: String
        let limit: Int?
    }
    private struct NoteHit: Encodable {
        let noteId: String
        let title: String
        let excerpt: String
    }
    private struct SearchNotesResult: Encodable {
        let results: [NoteHit]
    }
    private struct DecideConfirmationInput: Decodable {
        let id: String
        let decision: String
    }
    private struct DecideConfirmationResult: Encodable {
        let confirmationId: String
        let decision: String
    }
    private struct UpdateSettingsResult: Encodable {
        let accepted: Bool
    }
    /// Mirrors the bridge `getRecentActivity` payload wrapper `{ recentActivity: … }`.
    private struct RecentActivityEnvelope: Encodable {
        let recentActivity = Activity()
        struct Activity: Encodable {
            let commands: [String] = []
            let toolCalls: [String] = []
            let confirmations: [String] = []
            let modeSessions: [String] = []
            let errors: [String] = []
        }
    }

    private func receipt(for outcome: CommandRuntimeOutcome) -> CommandReceipt {
        switch outcome {
        case let .completed(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case let .awaitingConfirmation(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case .rejected:
            return CommandReceipt(commandId: "", accepted: false)
        }
    }

    private func decodePayload<T: Decodable>(_ request: CerebralHelmBridgeOperationRequest) -> T? {
        guard let data = try? JSONEncoder().encode(request.payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodePayload<T: Encodable>(_ value: T) -> [String: JSONAny] {
        guard
            let data = try? JSONEncoder().encode(value),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }

    // MARK: - Responses

    private func ok<T: Encodable>(
        _ request: CerebralHelmBridgeOperationRequest, payload: T
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: nil,
            messageID: request.messageID,
            operation: request.operation,
            payload: encodePayload(payload),
            schemaVersion: messageSchemaVersion,
            status: .ok,
            type: .bridgeOperationResponse
        )
    }

    private func errorResponse(
        _ request: CerebralHelmBridgeOperationRequest,
        category: CerebralContracts.Category,
        code: String,
        message: String
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: CerebralHelmBridgeOperationResponseError(
                category: category, code: code, details: nil, message: message, remediation: nil
            ),
            messageID: request.messageID,
            operation: request.operation,
            payload: [:],
            schemaVersion: messageSchemaVersion,
            status: .error,
            type: .bridgeOperationResponse
        )
    }

    private func invalidInput(
        _ request: CerebralHelmBridgeOperationRequest, _ message: String
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(request, category: .invalidInput, code: "bridge_invalid_input", message: message)
    }

    private func unimplemented(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(
            request,
            category: .unavailableCapability,
            code: "bridge_operation_unimplemented",
            message: "This bridge operation is not wired to the runtime yet."
        )
    }
}
