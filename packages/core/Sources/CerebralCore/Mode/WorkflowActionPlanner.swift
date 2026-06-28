import CerebralContracts

/// The authoritative planning facts the engine reads for one tool, sourced from
/// its validated descriptor (ADR-003): the descriptor's declared `risk` and
/// whether the tool is available before the macOS shell. Nothing else about a
/// tool influences a plan, so a workflow can never declare a weaker risk than the
/// descriptor allows.
public struct ToolPlanningFacts: Equatable, Sendable {
    public let risk: Risk
    public let availableInPreMac: Bool

    public init(risk: Risk, availableInPreMac: Bool) {
        self.risk = risk
        self.availableInPreMac = availableInPreMac
    }
}

/// The deterministic, config-driven action planner (NIC-38).
///
/// Resolves a mode application and a single quick action through one code path:
/// both become an ordered ``ModePlan`` of tool invocations. A mode resolves to its
/// associated workflow (single resolver); a quick action resolves to a workflow
/// directly. Per-step risk and pre-Mac availability come from the tool descriptor,
/// so the plan's aggregate risk (computed downstream by ``RiskAggregation``) is
/// never weaker than the strictest step (FR-MOD-03). Steps whose tool is not yet
/// available pre-Mac are planned as `.unavailable` rather than dropped, preserving
/// partial-success semantics (FR-MOD-04); a step naming an unknown tool is a
/// structured error, because a missing capability is a new tool, not a silent skip.
///
/// The engine is pure: the same inputs always yield an equal plan. It performs no
/// I/O — the composition layer loads workflow definitions and descriptor facts and
/// injects them.
public struct WorkflowActionPlanner: ActionPlanner {
    private let workflows: [String: CerebralHelmWorkflowDefinition]
    private let modeWorkflowIDs: [String: String]
    private let toolFacts: [String: ToolPlanningFacts]

    /// - Parameters:
    ///   - workflows: workflow/quick-action definitions keyed by id.
    ///   - modeWorkflowIDs: the workflow id each mode resolves to, keyed by mode id.
    ///   - toolFacts: descriptor-sourced planning facts keyed by tool id.
    public init(
        workflows: [String: CerebralHelmWorkflowDefinition],
        modeWorkflowIDs: [String: String],
        toolFacts: [String: ToolPlanningFacts]
    ) {
        self.workflows = workflows
        self.modeWorkflowIDs = modeWorkflowIDs
        self.toolFacts = toolFacts
    }

    public func plan(_ target: PlanTarget) throws -> ModePlan {
        switch target {
        case let .action(id):
            guard let workflow = workflows[id] else { throw ActionPlannerError.unknownAction(id) }
            return try resolve(subjectID: id, workflow: workflow)
        case let .mode(id):
            guard let workflowID = modeWorkflowIDs[id] else { throw ActionPlannerError.unknownMode(id) }
            // A mode's workflow id is configured, so a missing definition is a
            // broken config rather than an unknown request from the caller.
            guard let workflow = workflows[workflowID] else { throw ActionPlannerError.unknownAction(workflowID) }
            return try resolve(subjectID: id, workflow: workflow)
        }
    }

    private func resolve(subjectID: String, workflow: CerebralHelmWorkflowDefinition) throws -> ModePlan {
        let actions = try workflow.steps.map { step -> PlannedAction in
            guard let facts = toolFacts[step.tool] else {
                throw ActionPlannerError.unsupportedTool(action: workflow.id, tool: step.tool)
            }
            return PlannedAction(
                actionID: step.id,
                kind: step.tool,
                risk: facts.risk,
                status: facts.availableInPreMac ? .success : .unavailable,
                message: facts.availableInPreMac
                    ? nil
                    : "Tool '\(step.tool)' is unavailable before the macOS shell."
            )
        }
        return ModePlan(subjectID: subjectID, actions: actions)
    }
}
