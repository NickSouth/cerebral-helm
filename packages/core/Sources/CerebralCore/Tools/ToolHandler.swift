import Foundation

/// A bound tool implementation the executor invokes after validation.
///
/// The registry binds exactly one handler to each validated descriptor (NIC-28).
/// A handler receives input bytes that have already been validated against the
/// tool's input contract and returns output bytes. The executor (NIC-29) owns
/// policy evaluation, timeout, cancellation, and output validation around this
/// call, so a handler never decides whether it is allowed to run.
public protocol ToolHandler: Sendable {
    /// Must equal the id of the descriptor this handler is bound to.
    var toolID: String { get }

    /// Execute against already-validated input, returning output bytes.
    func execute(input: Data) async throws -> Data
}
