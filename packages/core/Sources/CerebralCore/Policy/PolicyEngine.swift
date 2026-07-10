import Foundation
import CerebralContracts

/// A stricter-only configuration overlay (PRD §10.3).
///
/// A user or machine layer may raise the minimum decision for a risk class but
/// never lower it. The engine folds these in with `max`, so an override can
/// escalate (e.g. `shell → deny`) but can never relax descriptor policy — passing
/// `.allow` for a class that already requires confirmation has no effect.
public struct PolicyOverrides: Sendable {
    public let minimumDecisions: [Risk: PolicyDecision]

    public init(minimumDecisions: [Risk: PolicyDecision] = [:]) {
        self.minimumDecisions = minimumDecisions
    }
}

public extension PolicyOverrides {
    /// Provisional MVP product policy: risk classes the MVP does not implement
    /// are denied outright rather than merely confirmed (PRD §3.2 non-goals — no
    /// purchases or financial actions; destructive capability is deferred). The
    /// engine does not apply this automatically; the composition layer opts in.
    static let mvpHardDenials = PolicyOverrides(minimumDecisions: [
        .destructive: .deny,
        .financial: .deny,
        .purchaseOrBooking: .deny,
    ])

    /// The "Ask before all actions" tightening (settings-driven): raises every
    /// non-read-only risk class to require confirmation. Read-only stays allowed — a
    /// status read is not an action. Stricter-only, so a class that already denies or
    /// confirms is unchanged; it can never relax descriptor policy.
    static let confirmEveryAction = PolicyOverrides(minimumDecisions: [
        .localWrite: .requireConfirmation,
        .externalWrite: .requireConfirmation,
        .shell: .requireConfirmation,
        .financial: .requireConfirmation,
        .purchaseOrBooking: .requireConfirmation,
        .destructive: .requireConfirmation,
    ])
}

/// A thread-safe, mutable holder for the active ``PolicyOverrides`` (NIC-137 live re-arm).
///
/// The policy engine stays a value type; when it holds a box, `evaluate` reads the box's
/// current overrides so a settings toggle (e.g. "Ask before all actions") re-arms
/// confirmation immediately, without recomposing the runtime. One box is shared by the
/// engine and its executor (both hold the same engine value), so a single write updates
/// every evaluation path. Overrides remain stricter-only — the box can only carry a floor.
public final class PolicyOverridesBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PolicyOverrides

    public init(_ value: PolicyOverrides = PolicyOverrides()) {
        self.value = value
    }

    public var current: PolicyOverrides {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

/// One tool invocation presented to the policy engine.
///
/// The risk class originates from the validated tool descriptor, never from the
/// caller, so a caller cannot declare a lower class. The only caller-supplied
/// signal is `callerRequestedConfirmation`, which can raise the decision but is
/// ignored when it would lower it (FR-SAF-02).
public struct PolicyRequest: Sendable {
    public let toolID: String
    public let declaredRisk: Risk
    public let runtimeRiskPolicy: RuntimeRiskPolicy
    public let plannedActionRisks: [Risk]
    public let shellInvocation: HookInvocation?
    public let callerRequestedConfirmation: Bool?

    public init(
        toolID: String,
        declaredRisk: Risk,
        runtimeRiskPolicy: RuntimeRiskPolicy = .descriptorRisk,
        plannedActionRisks: [Risk] = [],
        shellInvocation: HookInvocation? = nil,
        callerRequestedConfirmation: Bool? = nil
    ) {
        self.toolID = toolID
        self.declaredRisk = declaredRisk
        self.runtimeRiskPolicy = runtimeRiskPolicy
        self.plannedActionRisks = plannedActionRisks
        self.shellInvocation = shellInvocation
        self.callerRequestedConfirmation = callerRequestedConfirmation
    }
}

/// The engine's deterministic verdict for a request.
public struct PolicyEvaluation: Equatable, Sendable {
    public let decision: PolicyDecision
    /// The risk class that governed the decision. For a single tool this is the
    /// declared risk; for a `highest_planned_action` plan it is the strictest
    /// class among the declared risk and the planned actions.
    public let governingRisk: Risk
    public let reasonCode: String
    public let reason: String
}

/// Deterministically maps a tool's declared risk and runtime context to an
/// allow / require-confirmation / deny decision, outside any model (G-05,
/// ADR-003). Pure value type: the same request always yields the same verdict.
public struct PolicyEngine: Sendable {
    public let overrides: PolicyOverrides
    public let hookAllowlist: HookAllowlist
    /// When present, its `current` overrides supersede the static `overrides` on every
    /// evaluation, so a live settings toggle re-arms confirmation without recomposing the
    /// runtime (NIC-137). `nil` keeps the pure-value behavior everything else relies on.
    public let overridesBox: PolicyOverridesBox?

    public init(
        overrides: PolicyOverrides = PolicyOverrides(),
        hookAllowlist: HookAllowlist = HookAllowlist(),
        overridesBox: PolicyOverridesBox? = nil
    ) {
        self.overrides = overrides
        self.hookAllowlist = hookAllowlist
        self.overridesBox = overridesBox
    }

    public func evaluate(_ request: PolicyRequest) -> PolicyEvaluation {
        let considered = consideredRisks(for: request)
        let governingRisk = considered.max { $0.severityRank < $1.severityRank } ?? request.declaredRisk

        var (decision, reasonCode, reason) = baselineDecision(for: governingRisk, request: request)

        // Stricter-only escalations, folded in with `max` over every class the
        // request touches so a deny on any planned-action class still applies. A live
        // overrides box (when composed) supersedes the static overrides.
        let activeOverrides = overridesBox?.current ?? overrides
        let overrideFloor = considered.compactMap { activeOverrides.minimumDecisions[$0] }.max() ?? .allow
        if overrideFloor > decision {
            decision = overrideFloor
            reasonCode = "override.stricter_user_policy"
            reason = "A stricter configured policy raised the decision for risk '\(governingRisk.rawValue)'."
        }

        let callerFloor: PolicyDecision = (request.callerRequestedConfirmation == true) ? .requireConfirmation : .allow
        if callerFloor > decision {
            decision = callerFloor
            reasonCode = "confirm.caller_requested"
            reason = "The caller explicitly requested confirmation."
        }

        return PolicyEvaluation(decision: decision, governingRisk: governingRisk, reasonCode: reasonCode, reason: reason)
    }

    private func consideredRisks(for request: PolicyRequest) -> [Risk] {
        switch request.runtimeRiskPolicy {
        case .descriptorRisk:
            return [request.declaredRisk]
        case .highestPlannedAction:
            return [request.declaredRisk] + request.plannedActionRisks
        }
    }

    private func baselineDecision(for risk: Risk, request: PolicyRequest) -> (PolicyDecision, String, String) {
        switch risk {
        case .readOnly:
            return (.allow, "allow.read_only", "Read-only tools run without confirmation.")
        case .localWrite:
            // Local, reversible writes (capture a note, open a configured app/URL) run
            // without confirmation. Confirmation is reserved for irreversible or
            // external effects — see the gated classes below.
            return (.allow, "allow.local_write", "Local, reversible writes run without confirmation.")
        case .shell:
            if let invocation = request.shellInvocation, hookAllowlist.allows(invocation) {
                return (.allow, "allow.shell_allowlisted", "The exact shell invocation is explicitly allowlisted.")
            }
            return (.requireConfirmation, "confirm.shell", "Shell execution requires confirmation unless the exact invocation is allowlisted.")
        case .externalWrite, .destructive, .financial, .purchaseOrBooking:
            return (.requireConfirmation, "confirm.\(risk.rawValue)", "Risk class '\(risk.rawValue)' requires confirmation.")
        }
    }
}

extension Risk {
    /// Provisional severity ordering, used only to choose which class to *report*
    /// as the governing risk when aggregating a multi-action plan (FR-MOD-03,
    /// ADR-003). Read-only and local writes are allowed; the gated classes
    /// (external write, shell, financial, purchase, destructive) share the same
    /// requireConfirmation baseline, so this ordering only selects the reported label.
    var severityRank: Int {
        switch self {
        case .readOnly: return 0
        case .localWrite: return 1
        case .externalWrite: return 2
        case .shell: return 3
        case .financial: return 4
        case .purchaseOrBooking: return 5
        case .destructive: return 6
        }
    }
}
