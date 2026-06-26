import CerebralContracts

/// Aggregates the risk of a multi-step plan.
///
/// The result is at least as strict as the strictest planned action (FR-MOD-03,
/// ADR-003), so a mode containing a hook aggregates to `shell` and cannot bypass
/// shell confirmation. Uses the same provisional severity ordering the policy
/// engine applies for `highest_planned_action`.
public enum RiskAggregation {
    public static func highest(_ risks: [Risk]) -> Risk? {
        risks.max { $0.severityRank < $1.severityRank }
    }
}
