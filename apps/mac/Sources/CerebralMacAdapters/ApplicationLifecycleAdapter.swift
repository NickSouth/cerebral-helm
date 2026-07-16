#if canImport(AppKit)
import AppKit
import CerebralTools

/// Native ``ApplicationLifecycleCapability`` — the "close all windows" quit target
/// enumeration and graceful termination (NIC-143). Shares the permission-free
/// `NSRunningApplication` seam (``RunningApplicationSource``) with "Windows Stored by
/// Mode", so both are testable with the same fakes.
///
/// Enumeration returns every *regular* (Dock-visible) running app — including hidden
/// ones, unlike the workspace-windows capability — excluding the host. That naturally
/// spares background/menu-bar agents (activation policy `.accessory`/`.prohibited`),
/// matching the owner's "close every running app except CerebralHelm" intent. Quitting
/// is best-effort and graceful: a not-running id is simply absent from the result.
public struct MacApplicationLifecycleCapability: ApplicationLifecycleCapability {
    private let source: any RunningApplicationSource

    public init(source: any RunningApplicationSource = SystemRunningApplications()) {
        self.source = source
    }

    public func regularRunningApplicationBundleIDs() async throws -> [String] {
        // De-duplicate: several processes can share a bundle id.
        var seen = Set<String>()
        return source.runningApplications()
            .filter { $0.isRegular && $0.bundleID != source.ownBundleID }
            .map(\.bundleID)
            .filter { seen.insert($0).inserted }
    }

    public func quitApplications(bundleIDs: [String]) async throws -> [String] {
        bundleIDs.filter { $0 != source.ownBundleID && source.terminate(bundleID: $0) }
    }
}
#endif
