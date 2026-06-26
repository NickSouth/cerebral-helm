/// A categorized failure a tool handler raises so the executor can map it to a
/// stable error category (FR-TOL-06) without inspecting provider-specific types.
///
/// Handlers in `CerebralTools` translate native adapter errors into these cases;
/// the executor never sees a raw platform error.
public enum ToolHandlerError: Error, Equatable, Sendable {
    /// Input failed validation against the tool's input contract (FR-TOL-02).
    case invalidInput(String)
    /// The handler produced output that violates its output contract.
    case invalidOutput(String)
    /// A required capability or resource was unavailable (FR-SHL-06).
    case unavailable(String)
    /// The platform denied permission for the operation.
    case permissionDenied(String)
    /// An otherwise-unclassified provider failure.
    case providerFailure(String)
}
