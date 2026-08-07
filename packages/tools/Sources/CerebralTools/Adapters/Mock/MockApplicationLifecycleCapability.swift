import CerebralCore

/// Deterministic mock ``ApplicationLifecycleCapability`` for the "close all windows"
/// tool (NIC-143) and the host quit behind `shut-down`. `runningBundleIDs` simulates the
/// regular running applications; `quitApplications` reports exactly the requested ids that
/// are still "running", mirroring the native adapter's best-effort semantics without any
/// platform API. `quitHostApplication` records the request instead of terminating the test
/// process — the one capability whose real behavior a test can never exercise directly.
public final class MockApplicationLifecycleCapability: ApplicationLifecycleCapability, @unchecked Sendable {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var runningBundleIDs: [String]
    /// How many times a host quit was requested.
    public private(set) var hostQuitRequests = 0

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        runningBundleIDs: [String] = []
    ) {
        self.matrix = matrix
        self.fault = fault
        self.runningBundleIDs = runningBundleIDs
    }

    public func quitHostApplication() async throws {
        try CapabilityGate.check(CapabilityMatrix.Capability.applicationLifecycle, matrix: matrix, fault: fault)
        hostQuitRequests += 1
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
