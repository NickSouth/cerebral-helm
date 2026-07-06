import CerebralCore

/// Deterministic mock ``WorkspaceWindowsCapability`` ("Windows Stored by Mode",
/// NIC-85). `visibleBundleIDs` simulates the currently visible applications and
/// `runningBundleIDs` the wider running set, so hide returns what was visible and
/// unhide returns only ids that are still "running" — mirroring the native
/// adapter's best-effort semantics without any platform API.
public struct MockWorkspaceWindowsCapability: WorkspaceWindowsCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var visibleBundleIDs: [String]
    public var runningBundleIDs: Set<String>

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        visibleBundleIDs: [String] = [],
        runningBundleIDs: Set<String> = []
    ) {
        self.matrix = matrix
        self.fault = fault
        self.visibleBundleIDs = visibleBundleIDs
        self.runningBundleIDs = runningBundleIDs.union(visibleBundleIDs)
    }

    public func visibleApplicationBundleIDs() async throws -> [String] {
        try CapabilityGate.check(CapabilityMatrix.Capability.workspaceWindows, matrix: matrix, fault: fault)
        return visibleBundleIDs
    }

    public func hideApplications(bundleIDs: [String]) async throws -> [String] {
        try CapabilityGate.check(CapabilityMatrix.Capability.workspaceWindows, matrix: matrix, fault: fault)
        return bundleIDs.filter { visibleBundleIDs.contains($0) }
    }

    public func unhideApplications(bundleIDs: [String]) async throws -> [String] {
        try CapabilityGate.check(CapabilityMatrix.Capability.workspaceWindows, matrix: matrix, fault: fault)
        return bundleIDs.filter { runningBundleIDs.contains($0) }
    }
}
