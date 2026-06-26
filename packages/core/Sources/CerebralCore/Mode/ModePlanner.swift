import CerebralContracts

/// The outcome of one planned mode action.
public enum PlannedActionStatus: String, Equatable, Sendable {
    case success
    case failed
    case skipped
    case unavailable
}

/// One ordered action in a mode plan, with its risk class.
public struct PlannedAction: Equatable, Sendable {
    public let actionID: String
    public let kind: String
    public let risk: Risk
    public let status: PlannedActionStatus
    public let message: String?

    public init(actionID: String, kind: String, risk: Risk, status: PlannedActionStatus, message: String? = nil) {
        self.actionID = actionID
        self.kind = kind
        self.risk = risk
        self.status = status
        self.message = message
    }
}

/// A deterministic ordered plan for applying a mode (FR-MOD-02).
public struct ModePlan: Equatable, Sendable {
    public let modeID: String
    public let actions: [PlannedAction]

    public init(modeID: String, actions: [PlannedAction]) {
        self.modeID = modeID
        self.actions = actions
    }
}

public enum ModePlannerError: Error, Equatable, Sendable {
    case unknownMode(String)
}

/// Produces a deterministic ordered action plan for a mode.
///
/// The pre-Mac foundation binds a stub (`CerebralTools.StubModePlanner`); the
/// real planner that resolves apps, URLs, hooks, and widgets and executes them
/// is owned by PRE-MODE (NIC-38) and drops in behind this port. Composition
/// happens at the app layer, so `CerebralTools` never depends on the mode package.
public protocol ModePlanner: Sendable {
    func plan(modeID: String) throws -> ModePlan
}
