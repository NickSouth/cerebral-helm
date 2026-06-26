import CerebralCore

/// Deterministic stub mode planner for the pre-Mac foundation.
///
/// Stands in for the durable PRE-MODE planner (NIC-38) behind the Core
/// ``ModePlanner`` port. Its plans include mock per-action outcomes so mode.apply
/// can demonstrate aggregate risk (FR-MOD-03) and partial success (FR-MOD-04)
/// without real native execution.
public struct StubModePlanner: ModePlanner {
    private let plans: [String: ModePlan]

    public init(plans: [String: ModePlan]? = nil) {
        self.plans = plans ?? Self.defaultPlans
    }

    public func plan(modeID: String) throws -> ModePlan {
        guard let plan = plans[modeID] else { throw ModePlannerError.unknownMode(modeID) }
        return plan
    }

    public static let defaultPlans: [String: ModePlan] = [
        // Developer contains a setup hook, so its aggregate risk is `shell`.
        "developer": ModePlan(modeID: "developer", actions: [
            PlannedAction(actionID: "open-editor", kind: "app.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "open-repo", kind: "url.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "run-setup", kind: "hook.run", risk: .shell, status: .success),
        ]),
        // Executive opens apps only; one is missing, so it ends partial-success.
        "executive": ModePlan(modeID: "executive", actions: [
            PlannedAction(actionID: "open-dashboard", kind: "app.open", risk: .localWrite, status: .success),
            PlannedAction(actionID: "open-calendar", kind: "app.open", risk: .localWrite, status: .unavailable, message: "Configured application missing."),
        ]),
    ]
}
