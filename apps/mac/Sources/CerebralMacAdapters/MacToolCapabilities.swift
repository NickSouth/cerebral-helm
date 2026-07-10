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
    /// The composed native capability bundle plus the concrete adapters the
    /// shell needs directly: the status actor (the publisher streams the same
    /// instance's snapshots, sharing rate-metric delta state with the one-shot
    /// tool) and the Keychain secret store (NIC-82 — carried here rather than on
    /// `ToolCapabilities` because no tool handler consumes secrets in the MVP;
    /// config resolution and the settings provisioning flow are its consumers).
    public struct Composition {
        public let capabilities: ToolCapabilities
        public let systemStatus: MacSystemStatusCapability
        public let secretStore: KeychainSecretCapability
    }

    public static func make(
        references: CommandReferences,
        workspace: any WorkspaceOpening = SystemWorkspace()
    ) -> Composition {
        let systemStatus = MacSystemStatusCapability()
        let secretStore = KeychainSecretCapability()
        return Composition(
            capabilities: ToolCapabilities(
                app: NSWorkspaceAppCapability(apps: references.apps.mapValues(\.target), workspace: workspace),
                url: NSWorkspaceURLCapability(urls: references.urls.mapValues(\.target), workspace: workspace),
                process: ProcessHookCapability(),
                systemStatus: systemStatus,
                networkSpeedTest: MacNetworkSpeedTestCapability(),
                workspaceWindows: MacWorkspaceWindowsCapability(),
                window: AXWindowCapability(),
                appDiscovery: MacAppDiscoveryCapability(),
                nativeCapabilityIDs: [
                    CapabilityMatrix.Capability.appOpen,
                    CapabilityMatrix.Capability.urlOpen,
                    CapabilityMatrix.Capability.hookRun,
                    CapabilityMatrix.Capability.systemStatusRead,
                    CapabilityMatrix.Capability.networkSpeedTest,
                    CapabilityMatrix.Capability.secret,
                    CapabilityMatrix.Capability.workspaceWindows,
                    CapabilityMatrix.Capability.window,
                    CapabilityMatrix.Capability.appsList,
                ]
            ),
            systemStatus: systemStatus,
            secretStore: secretStore
        )
    }
}
#endif
