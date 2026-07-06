import Foundation
import Testing
import CerebralContracts
import CerebralCore
import CerebralTools

// NIC-38 (6b): the live, config-driven action planner built from the shipped
// descriptors and `config/workflows/*.json`. Proves the authored workflows, the
// descriptor-sourced risk/availability facts, and the `enter-<mode>` convention
// resolve end to end through one engine.

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

@Test("applying developer resolves through enter-developer and aggregates to shell")
func developerModeResolvesToShell() throws {
    let plan = try livePlanner().plan(modeID: "developer")

    #expect(plan.subjectID == "developer")
    #expect(plan.actions.contains { $0.kind == "hook.run" })
    // The hook makes the strictest step `shell` — the governing risk mode.apply
    // must confirm against (FR-MOD-03).
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .shell)
    // The read-only snapshot runs pre-Mac; the Mac-only steps plan unavailable.
    #expect(plan.actions.contains { $0.status == .success })
    #expect(plan.actions.contains { $0.status == .unavailable })
}

@Test("composed for the macOS phase, every developer step plans available")
func developerModePlansFullyAvailableOnMac() throws {
    // The same workflows and descriptors, with facts computed from
    // `availability.macOS`: every shipped tool is available on macOS, so no step
    // plans unavailable and the aggregate risk is unchanged.
    let plan = try livePlanner(phase: .macOS).plan(modeID: "developer")

    #expect(plan.actions.allSatisfy { $0.status == .success })
    #expect(RiskAggregation.highest(plan.actions.map(\.risk)) == .shell)
}

@Test("every shipped mode resolves to a non-empty plan")
func allModesResolve() throws {
    let planner = try livePlanner()
    for modeID in ["executive", "developer", "school", "entertainment"] {
        let plan = try planner.plan(modeID: modeID)
        #expect(!plan.actions.isEmpty)
    }
}

@Test("a quick action / workflow id resolves directly through the same engine")
func quickActionResolvesDirectly() throws {
    let plan = try livePlanner().plan(actionID: "enter-entertainment")

    #expect(plan.subjectID == "enter-entertainment")
    // The read-only system snapshot runs pre-Mac; the Mac-only app.open steps
    // carry localWrite risk and plan unavailable.
    #expect(plan.actions.contains { $0.risk == .localWrite })
    #expect(plan.actions.contains { $0.status == .success })
    #expect(plan.actions.contains { $0.status == .unavailable })
}

@Test("an unconfigured mode is a structured error on the live planner")
func unknownModeIsStructuredError() throws {
    #expect(throws: ActionPlannerError.unknownMode("ghost")) {
        _ = try livePlanner().plan(modeID: "ghost")
    }
}
