/// Resolves a configured hook id to its exact, fully-specified invocation.
///
/// Hooks are referenced by config id and never by free-form text (FR-SAF-03,
/// FR-TOL-05): the catalog is the only source of executable hook invocations, so
/// an id with no catalog entry cannot run. The pre-Mac foundation populates this
/// from fixtures; the Mac phase loads it from validated configuration.
public struct HookCatalog: Sendable {
    private let invocations: [String: HookInvocation]

    public init(_ invocations: [String: HookInvocation] = [:]) {
        self.invocations = invocations
    }

    public func invocation(for hookID: String) -> HookInvocation? {
        invocations[hookID]
    }

    public var hookIDs: [String] {
        invocations.keys.sorted()
    }
}
