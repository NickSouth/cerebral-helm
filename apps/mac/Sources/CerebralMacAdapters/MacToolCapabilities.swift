#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Composes the macOS capability bundle (NIC-78): honest native adapters where
/// they exist, and `.none`-matrix mocks for the slots whose native adapters have
/// not landed yet — so an invocation of those tools reports a truthful
/// `unavailable` instead of a mock success. Each adapter increment flips its slot
/// and adds its id to `nativeCapabilityIDs`, which also drives the bridge's
/// handshake capability flags (FR-SHL-06).
public enum MacToolCapabilities {
    /// The composed native capability bundle plus the concrete status actor the
    /// shell needs directly: the status publisher (NIC-81b) streams the same
    /// instance's rich snapshots, sharing the rate-metric delta state with the
    /// one-shot `system.status.read` tool.
    public struct Composition {
        public let capabilities: ToolCapabilities
        public let systemStatus: MacSystemStatusCapability
    }

    public static func make(
        references: CommandReferences,
        workspace: any WorkspaceOpening = SystemWorkspace()
    ) -> Composition {
        let systemStatus = MacSystemStatusCapability()
        return Composition(
            capabilities: ToolCapabilities(
                app: NSWorkspaceAppCapability(apps: references.apps.mapValues(\.target), workspace: workspace),
                url: NSWorkspaceURLCapability(urls: references.urls.mapValues(\.target), workspace: workspace),
                process: ProcessHookCapability(),
                systemStatus: systemStatus,
                nativeCapabilityIDs: [
                    CapabilityMatrix.Capability.appOpen,
                    CapabilityMatrix.Capability.urlOpen,
                    CapabilityMatrix.Capability.hookRun,
                    CapabilityMatrix.Capability.systemStatusRead,
                ]
            ),
            systemStatus: systemStatus
        )
    }
}
#endif
