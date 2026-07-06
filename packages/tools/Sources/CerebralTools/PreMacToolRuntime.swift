import Foundation
import CerebralContracts
import CerebralCore
import CerebralShared

/// Composition root for the portable tool runtime.
///
/// Assembles the validated registry, portable handlers, the injected capability
/// bundle (``ToolCapabilities`` — mocks by default, honest native adapters on
/// macOS), and the knowledge service into a ready `ToolExecutor`. This is where
/// the layers meet — descriptors are authoritative, policy is owned by the
/// engine, handlers are bound through the registry — without `CerebralTools`
/// depending on the knowledge package (the service is injected).
public enum PreMacToolRuntime {
    /// Builds the validated registry of portable handlers bound to the supplied
    /// capability bundle (mocks by default; the macOS shell injects honest native
    /// adapters through the same seam, FR-TOL-04).
    public static func makeRegistry(
        descriptorsDirectory: URL,
        capabilities: ToolCapabilities = .mocks(),
        knowledge: any KnowledgeService = MockKnowledgeService(),
        hookCatalog: HookCatalog = HookCatalog(),
        modePlanner: any ActionPlanner = StubModePlanner()
    ) throws -> ToolRegistry {
        let descriptors = try ToolDescriptorCatalog.loadDescriptors(directory: descriptorsDirectory)

        let handlers: [String: any ToolHandler] = [
            "app.open": AppOpenHandler(capability: capabilities.app),
            "url.open": URLOpenHandler(capability: capabilities.url),
            "system.status.read": SystemStatusReadHandler(capability: capabilities.systemStatus),
            "note.capture": NoteCaptureHandler(knowledge: knowledge),
            "note.search": NoteSearchHandler(knowledge: knowledge),
            "hook.run": HookRunHandler(catalog: hookCatalog, capability: capabilities.process),
            "mode.apply": ModeApplyHandler(planner: modePlanner),
        ]

        var builder = ToolRegistryBuilder()
        for descriptor in descriptors {
            guard let handler = handlers[descriptor.id] else { continue }
            try builder.register(descriptor: descriptor, handler: handler)
        }
        return builder.build()
    }

    /// Builds the live config-driven action planner (NIC-38).
    ///
    /// Reads each tool's authoritative descriptor for its risk and pre-Mac
    /// availability, loads the workflow catalog, and maps every configured mode to
    /// its apply-workflow by the `enter-<modeId>` convention (a mode that has no
    /// matching workflow is simply left unresolvable, surfacing as a structured
    /// `unknownMode` rather than a silent success). Composition lives here, at the
    /// tools layer, so the core engine stays pure and convention-free.
    public static func makeActionPlanner(
        descriptorsDirectory: URL,
        configDirectory: URL,
        phase: ExecutionPhase = .preMac
    ) throws -> WorkflowActionPlanner {
        let descriptors = try ToolDescriptorCatalog.loadDescriptors(directory: descriptorsDirectory)
        let toolFacts = Dictionary(uniqueKeysWithValues: descriptors.map { descriptor -> (String, ToolPlanningFacts) in
            let available = phase == .preMac ? descriptor.availability.preMAC : descriptor.availability.macOS
            return (descriptor.id, ToolPlanningFacts(risk: descriptor.risk, available: available))
        })

        let workflows = try WorkflowCatalogLoader.load(configDirectory: configDirectory)
        let modeIDs = try ReferenceCatalogLoader.load(configDirectory: configDirectory).modeIds
        var modeWorkflowIDs: [String: String] = [:]
        for modeID in modeIDs {
            let workflowID = "enter-\(modeID)"
            if workflows[workflowID] != nil { modeWorkflowIDs[modeID] = workflowID }
        }

        return WorkflowActionPlanner(
            workflows: workflows,
            modeWorkflowIDs: modeWorkflowIDs,
            toolFacts: toolFacts,
            validateStepInput: { toolID, input in try validateStepInput(toolID: toolID, input: input) }
        )
    }

    /// Validates one workflow step's static input against its tool's input schema.
    ///
    /// There is no generic JSON-Schema validator in Swift; the authoritative
    /// validation is each tool's generated input type Codable-decoding the input
    /// (the same gate every handler uses). This seam decodes the serialized step
    /// input into the matching generated type and throws on a mismatch, so a
    /// malformed step input surfaces as a structured `invalidStepInput` resolve
    /// error instead of failing only when the native adapter runs on macOS.
    ///
    /// Tools whose required set is empty (e.g. `system.status.read`) accept an
    /// empty object `{}`, which the planner passes for an absent step input. An
    /// unknown tool id validates trivially — the planner's `toolFacts` check
    /// already rejects unsupported tools before this seam runs.
    static func validateStepInput(toolID: String, input: Data?) throws {
        let data = input ?? Data("{}".utf8)
        switch toolID {
        case "app.open": _ = try CerebralHelmAppOpenInput(data: data)
        case "url.open": _ = try CerebralHelmURLOpenInput(data: data)
        case "hook.run": _ = try CerebralHelmHookRunInput(data: data)
        case "note.capture": _ = try CerebralHelmNoteCaptureInput(data: data)
        case "note.search": _ = try CerebralHelmNoteSearchInput(data: data)
        case "mode.apply": _ = try CerebralHelmModeApplyInput(data: data)
        case "system.status.read": _ = try CerebralHelmSystemStatusReadInput(data: data)
        default: break
        }
    }

    public static func makeExecutor(
        descriptorsDirectory: URL,
        capabilities: ToolCapabilities = .mocks(),
        knowledge: any KnowledgeService = MockKnowledgeService(),
        hookCatalog: HookCatalog = HookCatalog(),
        modePlanner: any ActionPlanner = StubModePlanner(),
        policy: PolicyEngine = PolicyEngine(),
        phase: ExecutionPhase = .preMac,
        clock: any TimeSource = SystemClock()
    ) throws -> ToolExecutor {
        let registry = try makeRegistry(
            descriptorsDirectory: descriptorsDirectory,
            capabilities: capabilities,
            knowledge: knowledge,
            hookCatalog: hookCatalog,
            modePlanner: modePlanner
        )
        return ToolExecutor(registry: registry, policy: policy, phase: phase, clock: clock)
    }
}
