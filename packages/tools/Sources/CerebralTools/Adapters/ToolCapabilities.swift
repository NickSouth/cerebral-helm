/// The bundle of native-capability implementations one composition binds beneath
/// the portable tool handlers (FR-TOL-04). Every slot satisfies one of the
/// protocols in `NativeCapabilities.swift`, implemented by either a deterministic
/// mock (pre-Mac foundation) or an honest macOS adapter (apps/mac). Handlers
/// never know which they got — both must satisfy the same contract suite.
///
/// `nativeCapabilityIDs` declares which slots carry honest native implementations,
/// by their stable ``CapabilityMatrix/Capability`` IDs; the mock factory declares
/// none. The
/// composition layer derives the bridge's capability flags from this set
/// (FR-SHL-06), so a mock-backed composition reports its native capabilities as
/// unavailable instead of pretending they work.
public struct ToolCapabilities: Sendable {
    public let app: any AppCapability
    public let url: any URLCapability
    public let process: any ProcessCapability
    public let systemStatus: any SystemStatusCapability
    /// Stable capability IDs (``CapabilityMatrix/Capability/appOpen`` etc.) bound
    /// to honest native implementations in this bundle. Empty for the mock bundle.
    public let nativeCapabilityIDs: Set<String>

    public init(
        app: any AppCapability,
        url: any URLCapability,
        process: any ProcessCapability,
        systemStatus: any SystemStatusCapability,
        nativeCapabilityIDs: Set<String> = []
    ) {
        self.app = app
        self.url = url
        self.process = process
        self.systemStatus = systemStatus
        self.nativeCapabilityIDs = nativeCapabilityIDs
    }

    /// The pre-Mac bundle: deterministic mocks gated by `matrix` (AC-32.2),
    /// declaring no native capability.
    public static func mocks(matrix: CapabilityMatrix = .allAvailable) -> ToolCapabilities {
        ToolCapabilities(
            app: MockAppCapability(matrix: matrix),
            url: MockURLCapability(matrix: matrix),
            process: MockProcessCapability(matrix: matrix),
            systemStatus: MockSystemStatusCapability(matrix: matrix)
        )
    }
}
