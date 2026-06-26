import CerebralContracts
import CerebralShared

/// One disclosed argument of a confirmable action.
public struct ConfirmationArgument: Equatable, Sendable {
    public let name: String
    public let value: String
    public let sensitive: Bool

    public init(name: String, value: String, sensitive: Bool) {
        self.name = name
        self.value = value
        self.sensitive = sensitive
    }
}

/// The exact facts being confirmed for one command.
///
/// The plan hash is computed over these fields, so any change to the tool,
/// destination, account, disclosure metadata, or arguments produces a different
/// hash and invalidates an outstanding confirmation (FR-SAF-05, AC-31.2). The
/// command id is deliberately *not* part of the hash: the hash identifies the
/// plan, and the token binds it to a specific command separately.
public struct ConfirmationPlan: Equatable, Sendable {
    public let commandID: String
    public let toolID: String
    public let toolVersion: String
    public let toolPurpose: String
    public let risk: Risk
    public let destination: String?
    public let accountOrService: String?
    public let dataLeavingDevice: DataLeavingDevice
    public let reversibility: Reversibility
    public let arguments: [ConfirmationArgument]
    public let actionSummary: String
    public let policyReason: String

    public init(
        commandID: String,
        toolID: String,
        toolVersion: String,
        toolPurpose: String,
        risk: Risk,
        destination: String?,
        accountOrService: String?,
        dataLeavingDevice: DataLeavingDevice,
        reversibility: Reversibility,
        arguments: [ConfirmationArgument],
        actionSummary: String,
        policyReason: String
    ) {
        self.commandID = commandID
        self.toolID = toolID
        self.toolVersion = toolVersion
        self.toolPurpose = toolPurpose
        self.risk = risk
        self.destination = destination
        self.accountOrService = accountOrService
        self.dataLeavingDevice = dataLeavingDevice
        self.reversibility = reversibility
        self.arguments = arguments
        self.actionSummary = actionSummary
        self.policyReason = policyReason
    }
}

/// Computes the `sha256:` plan hash carried by a confirmation disclosure and
/// bound into its single-use token.
public enum PlanHash {
    public static func compute(_ plan: ConfirmationPlan) -> String {
        // Unit separator (0x1F) cannot appear in the field values, so the joined
        // form is unambiguous.
        var parts: [String] = [
            plan.toolID,
            plan.toolVersion,
            plan.risk.rawValue,
            plan.destination ?? "",
            plan.accountOrService ?? "",
            plan.dataLeavingDevice.rawValue,
            plan.reversibility.rawValue,
            plan.actionSummary,
        ]
        for argument in plan.arguments {
            parts.append("\(argument.name)=\(argument.value)#\(argument.sensitive)")
        }
        let canonical = parts.joined(separator: "\u{1f}")
        return "sha256:\(SHA256.hexDigest(of: canonical))"
    }
}
