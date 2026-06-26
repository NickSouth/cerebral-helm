import CerebralCore

/// Deterministic mock native adapters for the pre-Mac foundation.
///
/// Every native capability protocol has a mock here (AC-32.1). Each one applies
/// the shared ``CapabilityGate`` — capability matrix then injected fault — before
/// returning a deterministic result, so capability flags drive unavailable states
/// (AC-32.2) and any canonical failure can be reproduced (AC-32.3). No mock
/// touches a real platform API, so they remain portable and pure.

public struct MockAppCapability: AppCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var alreadyRunningAppIDs: Set<String>

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, alreadyRunningAppIDs: Set<String> = []) {
        self.matrix = matrix
        self.fault = fault
        self.alreadyRunningAppIDs = alreadyRunningAppIDs
    }

    public func open(appID: String) async throws -> AppOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.appOpen, matrix: matrix, fault: fault, subject: appID)
        return AppOpenResult(appID: appID, launched: true, alreadyRunning: alreadyRunningAppIDs.contains(appID))
    }
}

public struct MockURLCapability: URLCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var resolvedURLs: [String: String]

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, resolvedURLs: [String: String] = [:]) {
        self.matrix = matrix
        self.fault = fault
        self.resolvedURLs = resolvedURLs
    }

    public func open(urlID: String) async throws -> URLOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.urlOpen, matrix: matrix, fault: fault, subject: urlID)
        return URLOpenResult(urlID: urlID, opened: true, resolvedURL: resolvedURLs[urlID] ?? "https://example.com/\(urlID)")
    }
}

public struct MockProcessCapability: ProcessCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var exitCode: Int
    public var stdout: String
    public var stderr: String
    public var durationMs: Int

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        exitCode: Int = 0,
        stdout: String = "",
        stderr: String = "",
        durationMs: Int = 0
    ) {
        self.matrix = matrix
        self.fault = fault
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }

    public func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.hookRun, matrix: matrix, fault: fault, subject: invocation.executable)
        return ProcessRunResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            environment: invocation.environment,
            timedOut: false,
            durationMs: durationMs
        )
    }
}

public struct MockSystemStatusCapability: SystemStatusCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    /// Per-metric availability override; any metric not listed reports `.available`.
    public var perMetricAvailability: [SystemMetricID: MetricAvailability]
    public var values: [SystemMetricID: Double]

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        perMetricAvailability: [SystemMetricID: MetricAvailability] = [:],
        values: [SystemMetricID: Double] = [:]
    ) {
        self.matrix = matrix
        self.fault = fault
        self.perMetricAvailability = perMetricAvailability
        self.values = values
    }

    public func readMetrics(_ ids: [SystemMetricID]) async throws -> [SystemMetricReading] {
        try CapabilityGate.check(CapabilityMatrix.Capability.systemStatusRead, matrix: matrix, fault: fault)
        let requested = ids.isEmpty ? SystemMetricID.allCases : ids
        return requested.map { id in
            let availability = perMetricAvailability[id] ?? .available
            let value = availability == .available ? values[id] : nil
            return SystemMetricReading(id: id, availability: availability, value: value, unit: Self.unit(for: id))
        }
    }

    private static func unit(for id: SystemMetricID) -> String? {
        switch id {
        case .cpu, .memory, .battery: return "percent"
        case .network: return "mbps"
        case .display: return nil
        }
    }
}

public struct MockSecretCapability: SecretCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var resolvableReferences: Set<String>

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, resolvableReferences: Set<String> = []) {
        self.matrix = matrix
        self.fault = fault
        self.resolvableReferences = resolvableReferences
    }

    public func resolve(reference: String) async throws -> SecretResolution {
        try CapabilityGate.check(CapabilityMatrix.Capability.secret, matrix: matrix, fault: fault, subject: reference)
        return SecretResolution(reference: reference, isResolved: resolvableReferences.contains(reference))
    }
}

public struct MockWindowCapability: WindowCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var windows: [WindowInfo]

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, windows: [WindowInfo] = []) {
        self.matrix = matrix
        self.fault = fault
        self.windows = windows
    }

    public func inspect() async throws -> [WindowInfo] {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault)
        return windows
    }
}
