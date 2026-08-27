import Foundation
import CerebralContracts

/// What the composer was asked to write (NIC-250).
///
/// Report-agnostic on purpose: the daily brief is the first surface, and the email report and the
/// playlist build are a snapshot and an instruction rather than a second composer. Nothing here
/// names a report.
public struct ReportCompositionRequest: Equatable, Sendable {
    /// The quick-action id, which selects the composer entry in configuration and becomes the
    /// document's `reportId`. The model never supplies it.
    public let reportID: String
    /// The typed data the Assembler gathered deterministically. Structural rather than typed
    /// because the composer cannot know the report: it serialises this and never interprets it,
    /// which is what lets one composer serve every surface.
    public let snapshot: JSONValue

    public init(reportID: String, snapshot: JSONValue) {
        self.reportID = reportID
        self.snapshot = snapshot
    }
}

/// A composition that produced a document.
public struct ComposedReport: Sendable {
    /// The full document, envelope included. The model supplied only `blocks`: `schemaVersion` and
    /// `reportId` are values the system already knows, and every failure in the first spike was a
    /// malformed envelope field rather than a malformed report. Narrowing the model's output to
    /// the part that needs judgement deleted that entire error class.
    public let document: CerebralHelmReportDocument
    public let usage: ModelUsage
    /// How many completions this took. Greater than one means the first was retried, which is
    /// worth surfacing: a composer that silently needs two attempts every time is a prompt problem
    /// wearing a success.
    public let attempts: Int

    public init(document: CerebralHelmReportDocument, usage: ModelUsage, attempts: Int) {
        self.document = document
        self.usage = usage
        self.attempts = attempts
    }
}

/// Why a composition produced no document.
///
/// The cases are separate because they need different recovery, which is the point finding 16 of
/// the decision log makes: a caller that only validates against the schema cannot tell "the model
/// was cut off" from "the model was wrong", and those are not the same problem. Truncation is a
/// budget that was too small; invalidity is a model that misunderstood; unavailability is not the
/// model's fault at all.
public enum ReportCompositionFailure: Equatable, Sendable {
    /// No model could be reached, none is configured for this report, or the runtime does not have
    /// it. The string is reader-facing: it is what the surface says instead of a brief.
    case unavailable(String)
    /// The request exceeded its wall-clock budget.
    case timedOut
    /// The caller cancelled. Not a failure — nothing went wrong, and a surface must not report a
    /// user changing their mind as a broken composition.
    case cancelled
    /// The model ran to its output cap and stopped mid-document. UNPARSEABLE rather than invalid:
    /// schema validation downstream would not even diagnose it.
    case truncated(attempts: Int)
    /// The model produced a complete document that does not fit the contract — a wrong leaf type,
    /// an unknown enum case, or a bound overrun.
    case invalid(reason: String, attempts: Int)

    /// What a surface shows in place of the report. Never a raw parse error: a reader cannot act
    /// on `/blocks/3/value must be string`, and a report that renders a decoder's complaint is
    /// worse than one that says it could not be written.
    public var readerFacingMessage: String {
        switch self {
        case let .unavailable(message): return message
        case .timedOut: return "The brief took too long to write."
        case .cancelled: return "The brief was cancelled."
        case .truncated: return "The brief ran long and was cut off."
        case .invalid: return "The brief couldn\u{2019}t be written just now."
        }
    }
}

public enum ReportCompositionOutcome: Sendable {
    case composed(ComposedReport)
    case failed(ReportCompositionFailure)
}
