import Foundation

/// Joins an Assembler to the Composer, per report (NIC-228).
///
/// The two halves of the seam are deliberately separate types — `assemble` reads providers into a
/// typed snapshot, `compose` turns a snapshot into blocks — and something has to hold them
/// together. That something is here, in the portable core, rather than in the app-layer closure
/// that will call it: this is where "which reports are model-composed" is decided, and a decision
/// living in `apps/mac` would be covered by no CI job at all.
///
/// Report-agnostic by construction. The daily brief is the first surface; the email report and the
/// playlist build are each an assembler registered here and an instruction in configuration, not a
/// second service.
public struct ReportCompositionService: Sendable {
    /// One assembler per report id. A report with no assembler is not model-composed, which is the
    /// same answer configuration gives for a report with no composer entry — two ways to opt out,
    /// both of them honest.
    private let assemblers: [String: @Sendable (Date) async -> JSONValue]
    private let composer: ReportComposer

    public init(
        assemblers: [String: @Sendable (Date) async -> JSONValue],
        composer: ReportComposer
    ) {
        self.assemblers = assemblers
        self.composer = composer
    }

    /// Assembles `reportID`'s snapshot and composes it.
    ///
    /// Never throws, for the same reason ``ReportComposer/compose(_:)`` does not: every failure here
    /// is a state a surface has to render honestly, and an error escaping would make "Ollama is not
    /// running" indistinguishable from a bug.
    public func compose(reportID: String, now: Date) async -> ReportCompositionOutcome {
        guard let assemble = assemblers[reportID] else {
            return .failed(.unavailable("This report isn\u{2019}t composed by a model."))
        }
        return await composer.compose(
            ReportCompositionRequest(reportID: reportID, snapshot: await assemble(now))
        )
    }

    /// Which reports this service can compose. Lets a caller answer "is this one model-composed"
    /// without spending an assembly to find out.
    public var composableReportIDs: Set<String> { Set(assemblers.keys) }
}
