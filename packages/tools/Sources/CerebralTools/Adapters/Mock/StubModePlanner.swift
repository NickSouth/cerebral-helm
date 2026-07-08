import CerebralCore

/// Deterministic stub action planner for tests and the pre-Mac foundation.
///
/// Stands in for the config-driven `WorkflowActionPlanner` (NIC-38) behind the
/// Core ``ActionPlanner`` port. Its plans include mock per-action outcomes so
/// workflow execution can demonstrate aggregate risk (FR-MOD-03) and partial
/// success (FR-MOD-04) without real native execution. `actionPlans` resolves
/// quick-action / workflow ids; the legacy mode plans remain for tests that
/// exercise `PlanTarget.mode` directly.
public struct StubModePlanner: ActionPlanner {
    private let plans: [String: ModePlan]
    private let actionPlans: [String: ModePlan]

    public init(plans: [String: ModePlan]? = nil, actionPlans: [String: ModePlan] = [:]) {
        self.plans = plans ?? Self.defaultPlans
        self.actionPlans = actionPlans
    }

    public func plan(_ target: PlanTarget) throws -> ModePlan {
        switch target {
        case let .mode(modeID):
            guard let plan = plans[modeID] else { throw ActionPlannerError.unknownMode(modeID) }
            return plan
        case let .action(actionID):
            guard let plan = actionPlans[actionID] else { throw ActionPlannerError.unknownAction(actionID) }
            return plan
        }
    }

    public static let defaultPlans: [String: ModePlan] = [
        // Developer contains a setup hook, so its aggregate risk is `shell`.
        "developer": ModePlan(subjectID: "developer", actions: [
            PlannedAction(actionID: "open-editor", kind: "app.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "open-repo", kind: "url.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "run-setup", kind: "hook.run", risk: .shell, status: .success),
        ]),
        // Executive opens apps only; one is missing, so it ends partial-success.
        "executive": ModePlan(subjectID: "executive", actions: [
            PlannedAction(actionID: "open-dashboard", kind: "app.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "open-calendar", kind: "app.open", risk: .localWrite, status: .unavailable, message: "Configured application missing."),
        ]),
    ]
}
