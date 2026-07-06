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
    public static func make(
        references: CommandReferences,
        workspace: any WorkspaceOpening = SystemWorkspace()
    ) -> ToolCapabilities {
        ToolCapabilities(
            app: NSWorkspaceAppCapability(apps: references.apps.mapValues(\.target), workspace: workspace),
            url: NSWorkspaceURLCapability(urls: references.urls.mapValues(\.target), workspace: workspace),
            process: ProcessHookCapability(),
            // NIC-81 (live system status provider) has not landed: honest unavailable.
            systemStatus: MockSystemStatusCapability(matrix: .none),
            nativeCapabilityIDs: [
                CapabilityMatrix.Capability.appOpen,
                CapabilityMatrix.Capability.urlOpen,
                CapabilityMatrix.Capability.hookRun,
            ]
        )
    }
}
#endif
