/// The deterministic outcome the policy engine assigns to a tool invocation
/// (FR-SAF-01..03, G-05).
///
/// Cases are ordered by strictness (`allow < requireConfirmation < deny`) so the
/// engine can combine several inputs — descriptor risk, a configured override,
/// and a caller hint — by taking the strictest with `max`. Every input can only
/// raise the decision, never lower it, which is how "callers cannot lower risk"
/// and "stricter overrides only" fall out of the arithmetic rather than special
/// cases.
public enum PolicyDecision: Sendable, Equatable, Comparable {
    /// Run immediately without confirmation.
    case allow
    /// Pause for policy-owned confirmation before running.
    case requireConfirmation
    /// Refuse: the invocation never reaches a handler.
    case deny

    private var strictness: Int {
        switch self {
        case .allow: return 0
        case .requireConfirmation: return 1
        case .deny: return 2
        }
    }

    public static func < (lhs: PolicyDecision, rhs: PolicyDecision) -> Bool {
        lhs.strictness < rhs.strictness
    }
}
