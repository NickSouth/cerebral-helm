import Foundation
import Testing
import CerebralContracts
import CerebralCore
import CerebralTools

// NIC-38 / NIC-85 re-scope: the live, config-driven action planner built from the
// shipped descriptors and `config/workflows/*.json`. Workflows are quick actions
// resolved by id; modes resolve to no workflow (a mode switch runs no steps).

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func livePlanner(phase: ExecutionPhase = .preMac) throws -> WorkflowActionPlanner {
    let root = repositoryRoot()
    return try PreMacToolRuntime.makeActionPlanner(
        descriptorsDirectory: root.appendingPathComponent("config/tools/descriptors", isDirectory: true),
        configDirectory: root.appendingPathComponent("config", isDirectory: true),
        phase: phase
    )
}

@Test("open-developer-layout resolves and aggregates to shell (FR-MOD-03)")
func developerLayoutResolvesToShell() throws {
    let plan = try livePlanner().plan(actionID: "open-developer-layout")

    #expect(plan.subjectID == "open-developer-layout")
    #expect(plan.actions.contains { $0.kind == "hook.run" })
    // The hook makes the strictest step `shell` — the governing risk the workflow
    // must confirm against (FR-MOD-03).
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .shell)
    // The read-only snapshot runs pre-Mac; the Mac-only steps plan unavailable.
    #expect(plan.actions.contains { $0.status == .success })
    #expect(plan.actions.contains { $0.status == .unavailable })
    // Every step carries its serialized input for execution.
    #expect(plan.actions.allSatisfy { $0.input != nil })
}

@Test("composed for the macOS phase, every developer-layout step plans available")
func developerLayoutPlansFullyAvailableOnMac() throws {
    let plan = try livePlanner(phase: .macOS).plan(actionID: "open-developer-layout")

    #expect(plan.actions.allSatisfy { $0.status == .success })
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .shell)
}

@Test("every shipped layout workflow resolves to a non-empty plan")
func allLayoutWorkflowsResolve() throws {
    let planner = try livePlanner()
    for actionID in [
        "open-executive-layout", "open-developer-layout",
        "open-school-layout", "open-entertainment-layout",
    ] {
        let plan = try planner.plan(actionID: actionID)
        #expect(!plan.actions.isEmpty)
    }
}

@Test("modes resolve to no workflow — a mode switch plans no steps (NIC-85 re-scope)")
func modesNoLongerResolveToWorkflows() throws {
    #expect(throws: ActionPlannerError.unknownMode("developer")) {
        _ = try livePlanner().plan(modeID: "developer")
    }
}

@Test("an unconfigured action is a structured error on the live planner")
func unknownActionIsStructuredError() throws {
    #expect(throws: ActionPlannerError.unknownAction("ghost")) {
        _ = try livePlanner().plan(actionID: "ghost")
    }
}
