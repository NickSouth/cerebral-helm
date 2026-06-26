import Foundation
import CerebralCore
import CerebralShared

/// Composition root for the pre-Mac tool runtime.
///
/// Assembles the validated registry, portable handlers, mock native adapters, and
/// mock knowledge service into a ready `ToolExecutor`. This is where the layers
/// meet — descriptors are authoritative, policy is owned by the engine, handlers
/// are bound through the registry — without `CerebralTools` depending on the
/// knowledge package (the service is injected). hook.run (NIC-33-B) and mode.apply
/// (NIC-33-C) are registered by later increments.
public enum PreMacToolRuntime {
    public static func makeExecutor(
        descriptorsDirectory: URL,
        capabilityMatrix: CapabilityMatrix = .allAvailable,
        knowledge: any KnowledgeService = MockKnowledgeService(),
        policy: PolicyEngine = PolicyEngine(),
        clock: any TimeSource = SystemClock()
    ) throws -> ToolExecutor {
        let descriptors = try ToolDescriptorCatalog.loadDescriptors(directory: descriptorsDirectory)

        let handlers: [String: any ToolHandler] = [
            "app.open": AppOpenHandler(capability: MockAppCapability(matrix: capabilityMatrix)),
            "url.open": URLOpenHandler(capability: MockURLCapability(matrix: capabilityMatrix)),
            "system.status.read": SystemStatusReadHandler(capability: MockSystemStatusCapability(matrix: capabilityMatrix)),
            "note.capture": NoteCaptureHandler(knowledge: knowledge),
            "note.search": NoteSearchHandler(knowledge: knowledge),
        ]

        var builder = ToolRegistryBuilder()
        for descriptor in descriptors {
            guard let handler = handlers[descriptor.id] else { continue }
            try builder.register(descriptor: descriptor, handler: handler)
        }

        return ToolExecutor(registry: builder.build(), policy: policy, clock: clock)
    }
}
