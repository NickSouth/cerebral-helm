import CerebralCore

/// Deterministic mock ``ApplicationLifecycleCapability`` for the "close all windows"
/// tool (NIC-143). `runningBundleIDs` simulates the regular running applications;
/// `quitApplications` reports exactly the requested ids that are still "running",
/// mirroring the native adapter's best-effort semantics without any platform API.
public struct MockApplicationLifecycleCapability: ApplicationLifecycleCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var runningBundleIDs: [String]

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        runningBundleIDs: [String] = []
    ) {
        self.matrix = matrix
        self.fault = fault
        self.runningBundleIDs = runningBundleIDs
    }

    public func regularRunningApplicationBundleIDs() async throws -> [String] {
        try CapabilityGate.check(CapabilityMatrix.Capability.applicationLifecycle, matrix: matrix, fault: fault)
        return runningBundleIDs
    }

    public func quitApplications(bundleIDs: [String]) async throws -> [String] {
        try CapabilityGate.check(CapabilityMatrix.Capability.applicationLifecycle, matrix: matrix, fault: fault)
        return bundleIDs.filter { runningBundleIDs.contains($0) }
    }
}
