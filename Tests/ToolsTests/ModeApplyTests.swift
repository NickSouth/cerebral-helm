import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-33-C (PRE-SAFETY-6): mode.apply aggregate-risk handler.
///
/// FR-MOD-03 mode risk ≥ highest planned action; FR-MOD-04 partial success.

@Test("mode.apply aggregates to the strictest planned action (FR-MOD-03)")
func modeApplyAggregatesToStrictestAction() async throws {
    let handler = ModeApplyHandler(planner: StubModePlanner())

    // Developer's plan contains a shell hook, so the aggregate risk is `shell`.
    let output = try await handler.execute(input: Data(#"{"modeId":"developer"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.aggregateRisk == .shell)
    #expect(decoded.status == .success)
    #expect(decoded.actions.count == 3)
}

@Test("mode.apply reports partial success when an action is unavailable (FR-MOD-04)")
func modeApplyReportsPartialSuccess() async throws {
    let handler = ModeApplyHandler(planner: StubModePlanner())

    let output = try await handler.execute(input: Data(#"{"modeId":"executive"}"#.utf8))
    let decoded = try CerebralHelmModeApplyOutput(data: output)
    #expect(decoded.aggregateRisk == .localWrite)
    #expect(decoded.status == .partialSuccess)
    #expect(decoded.actions.contains { $0.status == .unavailable })
}

@Test("mode.apply reports an unconfigured mode as unavailable")
func modeApplyRejectsUnknownMode() async throws {
    let handler = ModeApplyHandler(planner: StubModePlanner())

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
