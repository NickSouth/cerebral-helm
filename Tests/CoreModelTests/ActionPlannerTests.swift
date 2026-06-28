import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

// NIC-38: the deterministic, descriptor-driven action planner. A mode application
// and a single quick action resolve through one engine into one ``ModePlan``;
// per-step risk and pre-Mac availability come from the tool descriptor.

private func step(_ id: String, _ tool: String) -> Step {
    Step(id: id, input: nil, label: nil, tool: tool)
}

private func workflow(_ id: String, _ steps: [Step]) -> CerebralHelmWorkflowDefinition {
    CerebralHelmWorkflowDefinition(extensions: nil, id: id, label: id, schemaVersion: "1.0.0", steps: steps)
}

/// Descriptor-sourced facts mirroring the shipped tools: read-only tools are
/// available pre-Mac; the local-write/shell tools are Mac-only.
private let toolFacts: [String: ToolPlanningFacts] = [
    "system.status.read": ToolPlanningFacts(risk: .readOnly, availableInPreMac: true),
    "note.search": ToolPlanningFacts(risk: .readOnly, availableInPreMac: true),
    "app.open": ToolPlanningFacts(risk: .localWrite, availableInPreMac: false),
    "url.open": ToolPlanningFacts(risk: .localWrite, availableInPreMac: false),
    "hook.run": ToolPlanningFacts(risk: .shell, availableInPreMac: false),
]

private func makePlanner() -> WorkflowActionPlanner {
    let workflows = [
        "morning-brief": workflow("morning-brief", [
            step("system-snapshot", "system.status.read"),
            step("recent-notes", "note.search"),
            step("open-mail", "app.open"),
        ]),
        "check-system-status": workflow("check-system-status", [
            step("read-status", "system.status.read"),
        ]),
        "broken": workflow("broken", [
            step("sync-calendar", "calendar.sync"),
        ]),
    ]
    return WorkflowActionPlanner(
        workflows: workflows,
        modeWorkflowIDs: ["executive": "morning-brief"],
        toolFacts: toolFacts
    )
}

// MARK: - Quick action resolution (a quick action IS a workflow)

@Test("a multi-step quick action resolves to one ordered plan with descriptor risk and pre-Mac status")
func multiStepActionResolves() throws {
    let plan = try makePlanner().plan(actionID: "morning-brief")

    #expect(plan.subjectID == "morning-brief")
    #expect(plan.actions.map(\.kind) == ["system.status.read", "note.search", "app.open"])
    #expect(plan.actions.map(\.risk) == [.readOnly, .readOnly, .localWrite])
    // Read-only tools run pre-Mac; the Mac-only app.open is planned unavailable.
    #expect(plan.actions.map(\.status) == [.success, .success, .unavailable])
    // Aggregate risk is the strictest step — the same path mode.apply already uses.
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .localWrite)
}

@Test("a single-step quick action is simply a plan of N=1")
func singleStepActionResolves() throws {
    let plan = try makePlanner().plan(actionID: "check-system-status")

    #expect(plan.actions.count == 1)
    #expect(plan.actions[0].risk == .readOnly)
    #expect(plan.actions[0].status == .success)
}

@Test("an unknown quick-action id is a structured error")
func unknownActionThrows() {
    #expect(throws: ActionPlannerError.unknownAction("nope")) {
        _ = try makePlanner().plan(actionID: "nope")
    }
}

@Test("a step naming an unregistered tool is a structured error, never a silent skip")
func unsupportedToolThrows() {
    #expect(throws: ActionPlannerError.unsupportedTool(action: "broken", tool: "calendar.sync")) {
        _ = try makePlanner().plan(actionID: "broken")
    }
}

// MARK: - Mode resolution through the same engine (single resolver)

@Test("a mode resolves through its associated workflow into the same artifact")
func modeResolvesThroughWorkflow() throws {
    let planner = makePlanner()
    let modePlan = try planner.plan(modeID: "executive")
    let actionPlan = try planner.plan(actionID: "morning-brief")

    #expect(modePlan.subjectID == "executive")
    // Same ordered actions as the workflow it resolves to.
    #expect(modePlan.actions == actionPlan.actions)
}

@Test("an unconfigured mode is a structured error")
func unknownModeThrows() {
    #expect(throws: ActionPlannerError.unknownMode("school")) {
        _ = try makePlanner().plan(modeID: "school")
    }
}

// MARK: - Determinism

@Test("the same request always yields an equal plan")
func planningIsDeterministic() throws {
    let planner = makePlanner()
    #expect(try planner.plan(actionID: "morning-brief") == (try planner.plan(actionID: "morning-brief")))
}
