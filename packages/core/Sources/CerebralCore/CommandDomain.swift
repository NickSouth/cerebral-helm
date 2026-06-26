import CerebralContracts

// The command spine reuses the generated contract DTOs as its domain models
// rather than re-declaring parallel types, which keeps the Swift core from
// drifting away from the canonical JSON Schemas (the source of truth per
// ADR-002 and the repository boundary rules). These aliases give the spine
// transport-independent, readable names without inventing new shapes.

/// A versioned command envelope. All input sources converge on this type.
public typealias CommandEnvelope = CerebralHelmCommandEnvelope

/// An immutable lifecycle transition event.
public typealias CommandLifecycleEvent = CerebralHelmCommandLifecycleEvent

/// A structured terminal result for a completed command.
public typealias CommandTerminalResult = CerebralHelmCommandTerminalResult

/// A standalone structured error.
public typealias StructuredError = CerebralHelmStructuredError

/// The supported command sources (`dashboard`, `hotkey`, `cli`, …).
public typealias CommandSource = CerebralHelmCommandEnvelopeSource

/// A command lifecycle status (`received`, `planned`, … `cancelled`).
public typealias CommandStatus = PreviousStatus

/// A command's terminal status (`succeeded`, `failed`, `cancelled`).
public typealias TerminalStatus = CerebralHelmCommandTerminalResultStatus

/// The privacy block carried by every command (`sensitivity` + `cloudPolicy`).
public typealias CommandPrivacy = Privacy

/// Declared sensitivity of a command (`public` … `secret`).
public typealias CommandSensitivity = Sensitivity

/// Cloud transmission policy (`deny`, `ask`, `allow`).
public typealias CommandCloudPolicy = CloudPolicy

/// Contract-level constants for the command spine.
public enum CommandContract {
    /// Current command/event schema version. Matches the `^\d+\.\d+\.\d+$`
    /// pattern required by the contract schemas.
    public static let schemaVersion = "1.0.0"
}
