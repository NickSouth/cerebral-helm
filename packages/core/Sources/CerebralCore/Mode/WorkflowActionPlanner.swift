import Foundation
import CerebralContracts

/// The authoritative planning facts the engine reads for one tool, sourced from
/// its validated descriptor (ADR-003): the descriptor's declared `risk` and
/// whether the tool is available in the composed execution phase. The composition
/// layer computes `available` from the descriptor's per-phase availability flags
/// (``ExecutionPhase``), so the planner itself stays phase-agnostic. Nothing else
/// about a tool influences a plan, so a workflow can never declare a weaker risk
/// than the descriptor allows.
public struct ToolPlanningFacts: Equatable, Sendable {
    public let risk: Risk
    public let available: Bool

    public init(risk: Risk, available: Bool) {
        self.risk = risk
        self.available = available
    }
}

/// The deterministic, config-driven action planner (NIC-38).
///
/// Resolves a mode application and a single quick action through one code path:
/// both become an ordered ``ModePlan`` of tool invocations. A mode resolves to its
/// associated workflow (single resolver); a quick action resolves to a workflow
/// directly. Per-step risk and phase availability come from the tool descriptor,
/// so the plan's aggregate risk (computed downstream by ``RiskAggregation``) is
/// never weaker than the strictest step (FR-MOD-03). Steps whose tool is not
/// available in the composed phase are planned as `.unavailable` rather than
/// dropped, preserving partial-success semantics (FR-MOD-04); a step naming an
/// unknown tool is a structured error, because a missing capability is a new
/// tool, not a silent skip.
///
/// The engine is pure: the same inputs always yield an equal plan. It performs no
/// I/O — the composition layer loads workflow definitions and descriptor facts and
/// injects them.
public struct WorkflowActionPlanner: ActionPlanner {
    private let workflows: [String: CerebralHelmWorkflowDefinition]
    private let modeWorkflowIDs: [String: String]
    private let toolFacts: [String: ToolPlanningFacts]
    private let validateStepInput: @Sendable (_ toolID: String, _ input: Data?) throws -> Void

    /// - Parameters:
    ///   - workflows: workflow/quick-action definitions keyed by id.
    ///   - modeWorkflowIDs: the workflow id each mode resolves to, keyed by mode id.
    ///   - toolFacts: descriptor-sourced planning facts keyed by tool id.
    ///   - validateStepInput: validates one step's serialized static input against
    ///     its tool's input schema, throwing on a mismatch. The core stays portable
    ///     and the planner pure: the composition layer injects a validator that
    ///     decodes the input into each tool's generated input type. Defaults to a
    ///     no-op so construction sites that do not exercise input validation
    ///     (e.g. unit tests of resolution shape) compile and behave as before; the
    ///     live composition must inject a real validator.
    public init(
        workflows: [String: CerebralHelmWorkflowDefinition],
        modeWorkflowIDs: [String: String],
        toolFacts: [String: ToolPlanningFacts],
        validateStepInput: @escaping @Sendable (_ toolID: String, _ input: Data?) throws -> Void = { _, _ in }
    ) {
        self.workflows = workflows
        self.modeWorkflowIDs = modeWorkflowIDs
        self.toolFacts = toolFacts
        self.validateStepInput = validateStepInput
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
            // The workflow contract promises step inputs are validated against the
            // tool's input schema at resolve time. An absent input is treated as an
            // empty object `{}` so tools that require no input validate cleanly.
            let inputData = try serializeStepInput(step.input)
            do {
                try validateStepInput(step.tool, inputData)
            } catch {
                throw ActionPlannerError.invalidStepInput(
                    action: workflow.id,
                    step: step.id,
                    tool: step.tool,
                    reason: String(describing: error)
                )
            }
            return PlannedAction(
                actionID: step.id,
                kind: step.tool,
                risk: facts.risk,
                status: facts.available ? .success : .unavailable,
                message: facts.available
                    ? nil
                    : "Tool '\(step.tool)' is unavailable in this phase."
            )
        }
        return ModePlan(subjectID: subjectID, actions: actions)
    }

    /// Serializes a step's static input bindings to JSON `Data`. An absent input
    /// is rendered as an empty object `{}` rather than `nil`, so a tool that
    /// requires no input (e.g. `system.status.read`) still validates cleanly and
    /// the injected validator always receives well-formed JSON to decode.
    private func serializeStepInput(_ input: [String: JSONAny]?) throws -> Data {
        guard let input else { return Data("{}".utf8) }
        return try JSONEncoder().encode(input)
    }
}
