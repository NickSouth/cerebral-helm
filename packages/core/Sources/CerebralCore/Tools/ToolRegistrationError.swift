import CerebralContracts

/// Why a tool failed to register.
///
/// Registration is fail-fast: the first duplicate id, mismatched handler, or
/// weakening overlay aborts the build so an invalid tool never becomes reachable
/// (AC-28.1, AC-28.3). Each case maps to an `invalid_input` structured error.
public enum ToolRegistrationError: Error, Equatable {
    case duplicateID(String)
    case handlerIDMismatch(descriptorID: String, handlerID: String)
    case overlayToolMismatch(descriptorID: String, overlayID: String)
    case overlayChangesRisk(toolID: String, descriptorRisk: String, overlayRisk: String)
    case overlayWeakensTimeout(toolID: String, descriptorTimeoutMs: Int, overlayTimeoutMs: Int)
    case overlayWeakensAvailability(toolID: String)

    public var structuredError: StructuredError {
        StructuredError(category: .invalidInput, code: code, details: nil, message: message, remediation: nil)
    }

    private var code: String {
        switch self {
        case .duplicateID: return "registry.duplicate_id"
        case .handlerIDMismatch: return "registry.handler_id_mismatch"
        case .overlayToolMismatch: return "registry.overlay_tool_mismatch"
        case .overlayChangesRisk: return "registry.overlay_changes_risk"
        case .overlayWeakensTimeout: return "registry.overlay_weakens_timeout"
        case .overlayWeakensAvailability: return "registry.overlay_weakens_availability"
        }
    }

    public var message: String {
        switch self {
        case let .duplicateID(id):
            return "Tool '\(id)' is already registered."
        case let .handlerIDMismatch(descriptorID, handlerID):
            return "Handler '\(handlerID)' cannot be bound to descriptor '\(descriptorID)'."
        case let .overlayToolMismatch(descriptorID, overlayID):
            return "Config overlay '\(overlayID)' does not match descriptor '\(descriptorID)'."
        case let .overlayChangesRisk(toolID, descriptorRisk, overlayRisk):
            return "Config overlay for '\(toolID)' cannot change risk from '\(descriptorRisk)' to '\(overlayRisk)'."
        case let .overlayWeakensTimeout(toolID, descriptorTimeoutMs, overlayTimeoutMs):
            return "Config overlay for '\(toolID)' cannot extend the timeout from \(descriptorTimeoutMs)ms to \(overlayTimeoutMs)ms."
        case let .overlayWeakensAvailability(toolID):
            return "Config overlay for '\(toolID)' cannot enable a pre-Mac availability the descriptor disables."
        }
    }
}
