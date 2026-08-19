import Foundation

/// What one completion cost, as reported by the runtime (NIC-241).
///
/// Every figure is optional except the wall clock, because a runtime may omit any of them and a
/// fabricated zero would be worse than an honest absence — these numbers exist to be reasoned
/// about. Prefill matters more than decode for this workload: a large system prompt plus a
/// 29-tool manifest (~4,535 prompt tokens) is re-read on every turn unless the prefix cache hits.
public struct ModelUsage: Equatable, Sendable {
    /// Tokens in the prompt the runtime actually evaluated.
    public let promptTokens: Int?
    /// Tokens generated.
    public let outputTokens: Int?
    /// Prompt evaluation rate, tokens per second.
    public let prefillTokensPerSecond: Double?
    /// Generation rate, tokens per second.
    public let decodeTokensPerSecond: Double?
    /// Measured by the adapter, end to end — including queueing and any cold model load, which a
    /// runtime's own timings exclude. A ~70 s cold reload is invisible in `decodeTokensPerSecond`
    /// and unmissable here.
    public let wallDuration: Duration

    public init(
        promptTokens: Int? = nil,
        outputTokens: Int? = nil,
        prefillTokensPerSecond: Double? = nil,
        decodeTokensPerSecond: Double? = nil,
        wallDuration: Duration
    ) {
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.decodeTokensPerSecond = decodeTokensPerSecond
        self.wallDuration = wallDuration
    }

    /// Tokens per second from a count and a duration in **nanoseconds**, which is the unit local
    /// runtimes report. Returns nil rather than zero or infinity when either side is missing or
    /// zero: a rate that cannot be computed is not a rate of nought.
    ///
    /// Rounded to one decimal, matching `evals/lib/runtime.mjs` so a figure measured by the eval
    /// harness and one measured in the app are the same figure — and so binary floating point does
    /// not report 60 tok/s as 59.99999999999999.
    public static func rate(tokens: Int?, nanoseconds: Int?) -> Double? {
        guard let tokens, let nanoseconds, tokens > 0, nanoseconds > 0 else { return nil }
        let perSecond = (Double(tokens) / Double(nanoseconds)) * 1_000_000_000
        return (perSecond * 10).rounded() / 10
    }
}

/// A completion collected in full: the buffered view of a stream.
///
/// `thinking` is kept apart from `text` deliberately. When deliberation is enabled — which is the
/// exception, not the rule — it is the model reasoning to itself, and a caller that concatenated
/// it into `text` would render deliberation to the user as if it were the answer.
public struct ModelCompletion: Equatable, Sendable {
    public let text: String
    public let thinking: String?
    public let toolCalls: [ModelToolCall]
    public let usage: ModelUsage

    public init(text: String, thinking: String? = nil, toolCalls: [ModelToolCall] = [], usage: ModelUsage) {
        self.text = text
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.usage = usage
    }
}
