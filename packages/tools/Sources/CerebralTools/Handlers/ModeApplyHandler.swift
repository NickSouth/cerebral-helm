import Foundation
import CerebralContracts
import CerebralCore

/// `mode.apply`: switch the active mode (workspace re-scope, NIC-85).
///
/// A mode switch persists the new active mode and records a mode session
/// (FR-MOD-05/06) while carrying the active context forward unchanged. It runs
/// **no workflow steps** — opening apps, URLs, and hooks belongs to explicitly
/// triggered quick-action workflows (the `run <action>` path), so a mode switch
/// is a cheap, reversible local write that never needs plan-risk aggregation.
/// Optional window behaviors ("Windows Stored by Mode") attach here in a later
/// increment.
public struct ModeApplyHandler: ToolHandler {
    public let toolID = "mode.apply"
    private let modeIDs: Set<String>
    private let coordinator: ModeSessionCoordinator
    private let stateStore: any ModeStateStore
    private let configVersion: String
    /// Recorded as the session's activation source (FR-MOD-06). The handler does
    /// not see the command envelope, so the composition supplies the surface
    /// (every current caller reaches here through the command bus).
    private let sessionSource: String

    public init(
        modeIDs: Set<String>,
        coordinator: ModeSessionCoordinator,
        stateStore: any ModeStateStore,
        configVersion: String = ConfigValidator.schemaVersion,
        sessionSource: String = "command"
    ) {
        self.modeIDs = modeIDs
        self.coordinator = coordinator
        self.stateStore = stateStore
        self.configVersion = configVersion
        self.sessionSource = sessionSource
    }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmModeApplyInput
        do { decoded = try CerebralHelmModeApplyInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("mode.apply input does not match its contract.")
        }
        guard modeIDs.contains(decoded.modeID) else {
            throw ToolHandlerError.unavailable("Mode '\(decoded.modeID)' is not configured.")
        }

        // Context is persisted separately from mode (FR-MOD-05): the switch
        // carries the current context forward, never clears it.
        let context = (try? stateStore.loadActiveContext()) ?? nil
        do {
            try coordinator.recordApplication(
                modeID: decoded.modeID,
                context: context,
                source: sessionSource,
                result: .success,
                configVersion: configVersion
            )
        } catch {
            throw ToolHandlerError.providerFailure("The mode switch could not be persisted.")
        }

        return try CerebralHelmModeApplyOutput(
            actions: [],
            aggregateRisk: .localWrite,
            modeID: decoded.modeID,
            status: .success
        ).jsonData()
    }
}
