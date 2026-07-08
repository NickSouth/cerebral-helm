/// Management surface of a secret store (NIC-82, FR-CFG-03): create/update,
/// read, and delete a secret *value* behind its logical reference.
///
/// Deliberately separate from ``SecretCapability``: tools and config resolution
/// only ever ask "is this reference bound?" (`resolve` — the value never crosses
/// that port). The management surface exists for provisioning — the future
/// settings flow and the adapter contract tests — and its `readValue` result is
/// a live secret: callers must never log, persist, or embed it anywhere outside
/// the store itself.
public protocol SecretStoreManaging: Sendable {
    /// Creates the secret or replaces its value if the reference already exists.
    func store(reference: String, value: String) async throws
    /// The stored value. Throws `NativeCapabilityError.notFound` when the
    /// reference is unbound.
    func readValue(reference: String) async throws -> String
    /// Removes the secret. Throws `NativeCapabilityError.notFound` when the
    /// reference is unbound (a delete never silently no-ops, FR-CFG-03).
    func delete(reference: String) async throws
}
