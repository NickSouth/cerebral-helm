/// A fully-resolved hook invocation.
///
/// Hooks are referenced by config ID and resolved to an exact executable,
/// argument vector, working directory, and bounded environment (FR-SAF-03,
/// FR-TOL-05). The policy engine matches this whole value by equality, so any
/// variation in executable, arguments, working directory, or environment
/// invalidates an allowlist match — free-form shell text can never satisfy it.
public struct HookInvocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String
    public let environment: [String: String]

    public init(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

/// The set of exact hook invocations a user has explicitly trusted to run
/// without confirmation.
///
/// Empty by default: with no allowlist, every shell invocation requires
/// confirmation (FR-SAF-03). Membership is exact equality, never prefix or
/// substring matching.
public struct HookAllowlist: Equatable, Sendable {
    public let entries: [HookInvocation]

    public init(entries: [HookInvocation] = []) {
        self.entries = entries
    }

    /// `true` only when `invocation` exactly equals an allowlisted entry.
    public func allows(_ invocation: HookInvocation) -> Bool {
        entries.contains(invocation)
    }
}
