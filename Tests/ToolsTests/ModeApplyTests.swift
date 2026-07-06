import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// `mode.apply` after the workspace re-scope (NIC-85): a mode switch persists the
/// active mode and records a session (FR-MOD-05/06) and runs **no** workflow
/// steps — opening apps/URLs/hooks belongs to explicitly triggered quick actions.

private func makeHandler(
    stateStore: InMemoryModeStateStore = InMemoryModeStateStore(),
    sessionLog: InMemoryModeSessionLog = InMemoryModeSessionLog()
) -> ModeApplyHandler {
    ModeApplyHandler(
        modeIDs: ["developer", "executive"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: sessionLog),
        stateStore: stateStore
    )
}

@Test("mode.apply persists the active mode and records a session (FR-MOD-05/06)")
func modeApplyPersistsAndRecords() async throws {
    let stateStore = InMemoryModeStateStore()
    let sessionLog = InMemoryModeSessionLog()
    let handler = makeHandler(stateStore: stateStore, sessionLog: sessionLog)

    let output = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.modeID == "developer")
    #expect(decoded.status == .success)
    #expect(decoded.aggregateRisk == .localWrite)
    // No workflow steps run on a mode switch.
    #expect(decoded.actions.isEmpty)

    #expect(try stateStore.loadActiveModeID() == "developer")
    let sessions = try sessionLog.read()
    #expect(sessions.count == 1)
    #expect(sessions.first?.modeID == "developer")
    #expect(sessions.first?.result == .success)
}

@Test("mode.apply carries the active context forward unchanged (FR-MOD-05)")
func modeApplyPreservesContext() async throws {
    let stateStore = InMemoryModeStateStore()
    let sessionLog = InMemoryModeSessionLog()
    try stateStore.saveActiveContext(ProjectContext(id: "cerebralhelm", label: "CerebralHelm"))
    let handler = makeHandler(stateStore: stateStore, sessionLog: sessionLog)

    _ = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))

    #expect(try stateStore.loadActiveContext()?.id == "cerebralhelm")
    #expect(try sessionLog.read().first?.context?.id == "cerebralhelm")
}

@Test("mode.apply reports an unconfigured mode as unavailable")
func modeApplyRejectsUnknownMode() async throws {
    let handler = makeHandler()

    do {
        _ = try await handler.execute(input: Data(#"{"modeId":"nonexistent"}"#.utf8))
        Issue.record("An unconfigured mode must not succeed.")
    } catch let error as ToolHandlerError {
        guard case .unavailable = error else {
            Issue.record("Expected unavailable, got \(error)")
            return
        }
    }
}

@Test("a persistence failure is a provider failure, not a silent success")
func modeApplyReportsPersistenceFailure() async throws {
    struct FailingLog: ModeSessionLog {
        func append(_ session: ModeSession) throws { throw CocoaError(.fileWriteUnknown) }
        func read() throws -> [ModeSession] { [] }
    }
    let stateStore = InMemoryModeStateStore()
    let handler = ModeApplyHandler(
        modeIDs: ["developer"],
        coordinator: ModeSessionCoordinator(stateStore: stateStore, sessionLog: FailingLog()),
        stateStore: stateStore
    )

    do {
        _ = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
        Issue.record("A failed persistence must not report success.")
    } catch let error as ToolHandlerError {
        guard case .providerFailure = error else {
            Issue.record("Expected providerFailure, got \(error)")
            return
        }
    }
}
