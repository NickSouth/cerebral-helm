/// The platform phase the runtime is composed for (PRD §5): `.preMac` is the
/// portable foundation running against mock native adapters; `.macOS` is the
/// native shell running honest platform adapters.
///
/// Every tool descriptor declares availability per phase (`availability.preMac`
/// and `availability.macOS`); the executor gates each invocation on the flag
/// matching the composed phase. The phase is fixed at composition time — it is a
/// property of the running app surface, never of an individual command — so a
/// caller can no more choose its phase than it can choose a tool's risk.
public enum ExecutionPhase: String, Sendable, Equatable {
    case preMac
    case macOS
}
