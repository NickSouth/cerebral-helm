import Foundation
import CerebralContracts
import CerebralCore

/// `mode.apply` (NIC-33-C): plan and apply a configured mode with runtime risk at
/// least as strict as the strictest planned action (FR-MOD-03), supporting
/// partial success (FR-MOD-04).
///
/// The handler delegates planning to the ``ActionPlanner`` port, aggregates the
/// plan's risk, and reports a per-action result. Confirmation for the aggregate
/// risk is enforced upstream by the policy engine's `highest_planned_action`
/// path, so a mode containing a hook cannot bypass shell confirmation.
public struct ModeApplyHandler: ToolHandler {
    public let toolID = "mode.apply"
    private let planner: any ActionPlanner

    public init(planner: any ActionPlanner) { self.planner = planner }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmModeApplyInput
        do { decoded = try CerebralHelmModeApplyInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("mode.apply input does not match its contract.")
        }

        let plan: ModePlan
        do {
            plan = try planner.plan(modeID: decoded.modeID)
        } catch let ActionPlannerError.unknownMode(modeID) {
            throw ToolHandlerError.unavailable("Mode '\(modeID)' is not configured.")
        }

        let aggregateRisk = RiskAggregation.highest(plan.actions.map(\.risk)) ?? .localWrite
        let allSucceeded = plan.actions.allSatisfy { $0.status == .success }
        let actions = plan.actions.map { action in
            Action(
                actionID: action.actionID,
                kind: action.kind,
                message: action.message,
                risk: action.risk,
                status: ActionStatus(rawValue: action.status.rawValue) ?? .failed
            )
        }

        return try CerebralHelmModeApplyOutput(
            actions: actions,
            aggregateRisk: aggregateRisk,
            modeID: decoded.modeID,
            status: allSucceeded ? .success : .partialSuccess
        ).jsonData()
    }
}
