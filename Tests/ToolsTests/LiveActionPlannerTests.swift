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

@Test("open-developer-layout is synthesized from the layout and aggregates to local_write (NIC-142)")
func developerLayoutResolvesFromLayout() throws {
    let plan = try livePlanner().plan(actionID: "open-developer-layout")

    #expect(plan.subjectID == "open-developer-layout")
    // Windows-only: opening apps/URLs and arranging windows — never the legacy
    // hook/terminal/system-snapshot steps (those are not part of a layout).
    #expect(!plan.actions.contains { $0.kind == "hook.run" })
    #expect(plan.actions.contains { $0.kind == "app.open" })
    #expect(plan.actions.contains { $0.kind == "window.arrange" })
    // No shell step, so the governing risk is local_write (FR-MOD-03).
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .localWrite)
    // Every layout step is macOS-only, so pre-Mac they all plan unavailable.
    #expect(plan.actions.allSatisfy { $0.status == .unavailable })
    // Every step carries its serialized input for execution.
    #expect(plan.actions.allSatisfy { $0.input != nil })
}

@Test("composed for the macOS phase, every developer-layout step plans available")
func developerLayoutPlansFullyAvailableOnMac() throws {
    let plan = try livePlanner(phase: .macOS).plan(actionID: "open-developer-layout")

    #expect(plan.actions.allSatisfy { $0.status == .success })
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .localWrite)
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
