import CerebralContracts
import CerebralCore
import CerebralTools

/// Derives the bridge capability flags (FR-SHL-06) from what the composition
/// actually bound, so the handshake reports reality instead of a hardcoded list:
/// a native capability is available exactly when the runtime is composed for the
/// macOS phase *and* its slot carries an honest native implementation. The
/// pre-Mac mock composition therefore derives the same all-unavailable set the
/// shell reported before any adapter existed (`BridgeCapabilities.preAdapterDefault`),
/// and each adapter increment flips its own flag by declaring itself in the
/// bundle's `nativeCapabilityIDs` — no handshake edits required.
public enum CompositionCapabilities {
    /// Convenience over the bound bundle.
    public static func bridgeCapabilities(
        phase: ExecutionPhase,
        capabilities: ToolCapabilities
    ) -> [CerebralContracts.Capability] {
        bridgeCapabilities(phase: phase, nativeCapabilityIDs: capabilities.nativeCapabilityIDs)
    }

    public static func bridgeCapabilities(
        phase: ExecutionPhase,
        nativeCapabilityIDs: Set<String>
    ) -> [CerebralContracts.Capability] {
        func flag(_ id: String, boundTo toolCapabilityID: String, whenUnavailable reason: String) -> CerebralContracts.Capability {
            guard phase == .macOS, nativeCapabilityIDs.contains(toolCapabilityID) else {
                return CerebralContracts.Capability(available: false, degradedReason: reason, id: id, source: .unavailable)
            }
            return CerebralContracts.Capability(available: true, degradedReason: nil, id: id, source: .native)
        }

        return [
            CerebralContracts.Capability(available: true, degradedReason: nil, id: "bridge.bootstrap", source: .native),
            flag("native.app.open", boundTo: CapabilityMatrix.Capability.appOpen, whenUnavailable: "Opening applications is not available yet."),
            flag("native.url.open", boundTo: CapabilityMatrix.Capability.urlOpen, whenUnavailable: "Opening URLs is not available yet."),
            flag("native.hook.run", boundTo: CapabilityMatrix.Capability.hookRun, whenUnavailable: "Running configured hooks is not available yet."),
            flag("system.metrics", boundTo: CapabilityMatrix.Capability.systemStatusRead, whenUnavailable: "Live system metrics are not available yet."),
            // No weather provider exists in the MVP; the flag stays honest.
            CerebralContracts.Capability(available: false, degradedReason: "Weather is not available yet.", id: "weather", source: .unavailable),
            // Battery rides the system-status adapter; whether this machine has a
            // battery is a runtime per-metric reading, not a composition fact.
            flag("battery", boundTo: CapabilityMatrix.Capability.systemStatusRead, whenUnavailable: "Battery status is not available yet."),
        ]
    }
}
