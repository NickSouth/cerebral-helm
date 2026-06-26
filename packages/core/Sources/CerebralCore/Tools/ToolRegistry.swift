import CerebralContracts

/// A descriptor that passed validation, with its bound handler and the effective
/// operational metadata after any stricter-only overlay is applied.
public struct RegisteredTool: Sendable {
    public let descriptor: CerebralHelmToolDescriptor
    public let handler: any ToolHandler
    /// Descriptor timeout, possibly shortened by a stricter config overlay.
    public let effectiveTimeoutMs: Int
    /// Descriptor pre-Mac availability, possibly disabled by a stricter overlay.
    public let availableInPreMac: Bool

    public var id: String { descriptor.id }
    public var risk: Risk { descriptor.risk }
}

/// The validated tool registry: the single source of bound, executable tools
/// (ADR-003). Rich descriptors are authoritative; the registry rejects any
/// invalid or duplicate registration so every tool it exposes is safe to run.
public struct ToolRegistry: Sendable {
    private let toolsByID: [String: RegisteredTool]

    fileprivate init(toolsByID: [String: RegisteredTool]) {
        self.toolsByID = toolsByID
    }

    /// All registered tools, sorted by id for a stable CLI and settings listing
    /// (AC-28.2).
    public var registeredTools: [RegisteredTool] {
        toolsByID.values.sorted { $0.id < $1.id }
    }

    /// Registered tool ids, sorted.
    public var toolIDs: [String] {
        toolsByID.keys.sorted()
    }

    public func tool(_ id: String) -> RegisteredTool? {
        toolsByID[id]
    }

    /// The handler bound to `id`, or `nil`. A handler is reachable only after its
    /// descriptor passed validation, so this never returns an unvalidated handler
    /// (AC-28.3).
    public func handler(for id: String) -> (any ToolHandler)? {
        toolsByID[id]?.handler
    }
}

/// Builds a ``ToolRegistry``, validating each registration as it is added.
///
/// ``ToolRegistry`` has no other initializer, so every tool it exposes passed
/// through `register`. A stricter-only config overlay (``ConfiguredTool``) may be
/// supplied to tighten operational limits; it may never weaken descriptor policy
/// (PRD §10.3).
public struct ToolRegistryBuilder {
    private var toolsByID: [String: RegisteredTool] = [:]

    public init() {}

    public mutating func register(
        descriptor: CerebralHelmToolDescriptor,
        handler: any ToolHandler,
        overlay: ConfiguredTool? = nil
    ) throws {
        guard handler.toolID == descriptor.id else {
            throw ToolRegistrationError.handlerIDMismatch(descriptorID: descriptor.id, handlerID: handler.toolID)
        }
        guard toolsByID[descriptor.id] == nil else {
            throw ToolRegistrationError.duplicateID(descriptor.id)
        }

        var effectiveTimeoutMs = descriptor.timeoutMS
        var availableInPreMac = descriptor.availability.preMAC

        if let overlay {
            guard overlay.id == descriptor.id else {
                throw ToolRegistrationError.overlayToolMismatch(descriptorID: descriptor.id, overlayID: overlay.id)
            }
            // Descriptor risk is authoritative; an overlay may not change it.
            guard overlay.risk == descriptor.risk.rawValue else {
                throw ToolRegistrationError.overlayChangesRisk(
                    toolID: descriptor.id,
                    descriptorRisk: descriptor.risk.rawValue,
                    overlayRisk: overlay.risk
                )
            }
            // Stricter-only: an overlay may shorten a timeout but never extend it.
            guard overlay.timeoutMs <= descriptor.timeoutMS else {
                throw ToolRegistrationError.overlayWeakensTimeout(
                    toolID: descriptor.id,
                    descriptorTimeoutMs: descriptor.timeoutMS,
                    overlayTimeoutMs: overlay.timeoutMs
                )
            }
            // Stricter-only: an overlay may disable a pre-Mac tool but never
            // enable one the descriptor marks unavailable.
            if overlay.availableInPreMac && !descriptor.availability.preMAC {
                throw ToolRegistrationError.overlayWeakensAvailability(toolID: descriptor.id)
            }
            effectiveTimeoutMs = min(descriptor.timeoutMS, overlay.timeoutMs)
            availableInPreMac = descriptor.availability.preMAC && overlay.availableInPreMac
        }

        toolsByID[descriptor.id] = RegisteredTool(
            descriptor: descriptor,
            handler: handler,
            effectiveTimeoutMs: effectiveTimeoutMs,
            availableInPreMac: availableInPreMac
        )
    }

    public func build() -> ToolRegistry {
        ToolRegistry(toolsByID: toolsByID)
    }
}
