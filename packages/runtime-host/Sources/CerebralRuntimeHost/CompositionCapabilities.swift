import Foundation
import CerebralContracts
import CerebralCore
import CerebralTools

/// Derives the bridge capability flags (FR-SHL-06) from what the composition
/// actually bound, so the handshake reports reality instead of a hardcoded list:
/// a native capability is available exactly when the runtime is composed for the
/// macOS phase, its slot carries an honest native implementation, *and* every
/// platform permission its tools require is satisfied (NIC-83, FR-SAF-07). The
/// pre-Mac mock composition therefore derives the same all-unavailable set the
/// shell reported before any adapter existed (`BridgeCapabilities.preAdapterDefault`),
/// and each adapter increment flips its own flag by declaring itself in the
/// bundle's `nativeCapabilityIDs` — no handshake edits required.
///
/// A permission-blocked capability degrades with guidance (why it is needed and
/// the System Settings deep link when one exists) instead of prompting — denied
/// platform permissions become capability errors, never repeated prompts or
/// bypass attempts.
public enum CompositionCapabilities {
    /// Convenience over the bound bundle.
    public static func bridgeCapabilities(
        phase: ExecutionPhase,
        capabilities: ToolCapabilities,
        requiredPermissions: [String: Set<String>] = [:],
        permissions: (any PermissionChecking)? = nil
    ) -> [CerebralContracts.Capability] {
        bridgeCapabilities(
            phase: phase,
            nativeCapabilityIDs: capabilities.nativeCapabilityIDs,
            requiredPermissions: requiredPermissions,
            permissions: permissions
        )
    }

    /// - Parameters:
    ///   - requiredPermissions: logical permission ids each *tool capability* id
    ///     requires (build from descriptors via ``requiredPermissionsByCapability(_:)``).
    ///   - permissions: the platform permission checker; `nil` (pre-Mac / tests
    ///     without a platform) treats every permission as satisfied so the
    ///     derivation is unchanged for existing compositions.
    public static func bridgeCapabilities(
        phase: ExecutionPhase,
        nativeCapabilityIDs: Set<String>,
        requiredPermissions: [String: Set<String>] = [:],
        permissions: (any PermissionChecking)? = nil
    ) -> [CerebralContracts.Capability] {
        func blockedPermission(_ toolCapabilityID: String) -> String? {
            guard let permissions else { return nil }
            let required = requiredPermissions[toolCapabilityID] ?? []
            return required.sorted().first { !permissions.status(of: $0).satisfiesRequirement }
        }

        func flag(_ id: String, boundTo toolCapabilityID: String, whenUnavailable reason: String) -> CerebralContracts.Capability {
            guard phase == .macOS, nativeCapabilityIDs.contains(toolCapabilityID) else {
                return CerebralContracts.Capability(available: false, degradedReason: reason, id: id, source: .unavailable)
            }
            if let blocked = blockedPermission(toolCapabilityID) {
                let guidance = PermissionCatalog.guidance(for: blocked)
                let link = guidance.settingsDeepLink.map { " Grant it in System Settings: \($0)" } ?? ""
                return CerebralContracts.Capability(
                    available: false,
                    degradedReason: guidance.explanation + link,
                    id: id,
                    source: .unavailable
                )
            }
            return CerebralContracts.Capability(available: true, degradedReason: nil, id: id, source: .native)
        }

        return [
            CerebralContracts.Capability(available: true, degradedReason: nil, id: "bridge.bootstrap", source: .native),
            flag("native.app.open", boundTo: CapabilityMatrix.Capability.appOpen, whenUnavailable: "Opening applications is not available yet."),
            flag("native.url.open", boundTo: CapabilityMatrix.Capability.urlOpen, whenUnavailable: "Opening URLs is not available yet."),
            flag("native.hook.run", boundTo: CapabilityMatrix.Capability.hookRun, whenUnavailable: "Running configured hooks is not available yet."),
            flag("system.metrics", boundTo: CapabilityMatrix.Capability.systemStatusRead, whenUnavailable: "Live system metrics are not available yet."),
            flag("native.workspace.windows", boundTo: CapabilityMatrix.Capability.workspaceWindows, whenUnavailable: "Windows Stored by Mode applies on the macOS host."),
            // No weather provider exists in the MVP; the flag stays honest.
            CerebralContracts.Capability(available: false, degradedReason: "Weather is not available yet.", id: "weather", source: .unavailable),
            // Battery rides the system-status adapter; whether this machine has a
            // battery is a runtime per-metric reading, not a composition fact.
            flag("battery", boundTo: CapabilityMatrix.Capability.systemStatusRead, whenUnavailable: "Battery status is not available yet."),
        ]
    }

    /// Folds descriptors into the permission map the derivation consumes:
    /// each descriptor's `requiredPermissions` apply to every tool-capability id
    /// in its `adapterRequirements.capabilities` (descriptors are authoritative
    /// for permission metadata, ADR-003).
    public static func requiredPermissionsByCapability(
        _ descriptors: [CerebralHelmToolDescriptor]
    ) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for descriptor in descriptors {
            for capabilityID in descriptor.adapterRequirements.capabilities {
                map[capabilityID, default: []].formUnion(descriptor.requiredPermissions)
            }
        }
        return map
    }
}
