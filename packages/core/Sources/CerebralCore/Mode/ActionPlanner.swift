import Foundation
import CerebralContracts

/// The outcome of one planned action.
public enum PlannedActionStatus: String, Equatable, Sendable {
    case success
    case failed
    case skipped
    case unavailable
}

/// One ordered action in a plan, with its risk class.
public struct PlannedAction: Equatable, Sendable {
    public let actionID: String
    public let kind: String
    public let risk: Risk
    public let status: PlannedActionStatus
    public let message: String?
    /// The step's serialized, already-validated static input — what the runner
    /// hands the tool when the plan executes. `nil` for plans that only preview.
    public let input: Data?

    public init(
        actionID: String, kind: String, risk: Risk, status: PlannedActionStatus,
        message: String? = nil, input: Data? = nil
    ) {
        self.actionID = actionID
        self.kind = kind
        self.risk = risk
        self.status = status
        self.message = message
        self.input = input
    }
}

/// A deterministic ordered plan of tool invocations (FR-MOD-02).
///
/// A mode application and a single quick action resolve to this same artifact; a
/// single-step action is simply `actions.count == 1`. `subjectID` names what was
/// planned — a mode id when planning a mode, a workflow/action id otherwise.
public struct ModePlan: Equatable, Sendable {
    public let subjectID: String
    public let actions: [PlannedAction]

    public init(subjectID: String, actions: [PlannedAction]) {
        self.subjectID = subjectID
        self.actions = actions
    }
}

/// What a caller asks the planner to resolve. The planner exposes one resolver so
/// a mode application and a quick action share a single, deterministic code path
/// (a quick action *is* a workflow): there is no separate quick-action runner.
public enum PlanTarget: Equatable, Sendable {
    /// A configured mode, resolved through the mode's associated workflow.
    case mode(String)
    /// A workflow / quick-action id, resolved directly.
    case action(String)
}

public enum ActionPlannerError: Error, Equatable, Sendable {
    /// No configured mode matches the requested id.
    case unknownMode(String)
    /// No workflow / quick action matches the requested id.
    case unknownAction(String)
    /// A workflow step names a tool the planner cannot resolve. The workflow is
    /// malformed: a missing capability is a new tool, never a silent skip.
    case unsupportedTool(action: String, tool: String)
    /// A workflow step's static input does not satisfy its tool's input schema.
    /// The workflow contract promises step inputs are validated against the tool's
    /// input schema at resolve time, so a malformed input is a structured resolve
    /// error here rather than a deferred failure when the native adapter runs.
    case invalidStepInput(action: String, step: String, tool: String, reason: String)
}

/// Produces a deterministic ordered action plan for a mode or a quick action.
///
/// One resolver, two callers (locked decision): `plan(_:)` is the single entry
/// point; `plan(modeID:)` and `plan(actionID:)` are thin conveniences over it. The
/// pre-Mac foundation binds a stub (`CerebralTools.StubModePlanner`); the
/// config-driven `WorkflowActionPlanner` drops in behind this same port.
public protocol ActionPlanner: Sendable {
    func plan(_ target: PlanTarget) throws -> ModePlan
}

public extension ActionPlanner {
    /// Resolve a mode application into an ordered plan.
    func plan(modeID: String) throws -> ModePlan { try plan(.mode(modeID)) }

    /// Resolve a single quick action / workflow into an ordered plan.
    func plan(actionID: String) throws -> ModePlan { try plan(.action(actionID)) }
}
