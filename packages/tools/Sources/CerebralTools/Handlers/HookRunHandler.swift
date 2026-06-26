import Foundation
import CerebralContracts
import CerebralCore

/// `hook.run` (NIC-33-B): execute a configured allowlisted hook, never arbitrary
/// shell text.
///
/// The handler resolves the requested hook id through the ``HookCatalog``. An id
/// with no catalog entry is rejected before any process is touched, so free-form
/// input cannot reach execution (AC-33.2). Confirmation for the shell risk class
/// is enforced upstream by the policy engine and confirmation coordinator; this
/// handler only runs the exact, pre-resolved invocation.
public struct HookRunHandler: ToolHandler {
    public let toolID = "hook.run"
    private let catalog: HookCatalog
    private let capability: any ProcessCapability

    public init(catalog: HookCatalog, capability: any ProcessCapability) {
        self.catalog = catalog
        self.capability = capability
    }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmHookRunInput
        do { decoded = try CerebralHelmHookRunInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("hook.run input does not match its contract.")
        }
        guard let invocation = catalog.invocation(for: decoded.hookID) else {
            throw ToolHandlerError.invalidInput("Hook '\(decoded.hookID)' is not a registered hook.")
        }
        do {
            let result = try await capability.run(invocation)
            return try CerebralHelmHookRunOutput(
                durationMS: result.durationMs,
                environment: result.environment,
                exitCode: result.exitCode,
                hookID: decoded.hookID,
                stderr: result.stderr,
                stdout: result.stdout,
                timedOut: result.timedOut
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}
