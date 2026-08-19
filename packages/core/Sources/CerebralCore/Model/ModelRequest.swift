import Foundation

/// What shape the caller is asking the runtime to produce.
///
/// **This is a request, not a guarantee.** Ollama accepts a JSON Schema under `format:` and still
/// emitted `value: 0` where a string was required — its structured output does not enforce leaf
/// types (ADR-009 Context). A caller must validate what it gets back. Guaranteed-valid output
/// needs grammar-constrained decoding, which is the seam NIC-249 fills; when it lands it becomes a
/// case here, and ``ModelRuntimeCapabilities/enforcesResponseSchema`` is how a caller tells the two
/// situations apart today.
public enum ModelResponseFormat: Equatable, Sendable {
    case text
    /// Ask the runtime to shape output to this JSON Schema, best-effort.
    case jsonSchema(JSONValue)
}

/// How long a model stays resident after serving a request (NIC-243, ADR-009).
///
/// Residency is a memory decision, and an expensive one: two resident 30B models measured ~51 GB
/// against a ~48 GB GPU budget and drove 18 GB of swap. It is expressed here, in the port's
/// vocabulary, so an adapter has something to translate; *which* profile gets which residency is
/// configuration (NIC-243), never a per-call decision by a caller.
public enum ModelResidency: Equatable, Sendable {
    /// Stay loaded indefinitely. For an always-on surface, where a ~70 s cold reload would be felt
    /// on every interaction.
    case pinned
    /// Stay loaded for a bounded idle window.
    case bounded(Duration)
    /// Unload as soon as the request completes. For a rare specialist that would otherwise hold
    /// tens of gigabytes against a surface someone is actually using.
    case evictAfterUse
}

/// The knobs a caller may turn per request.
///
/// `contextTokens` is mandatory and has no default on purpose. Left unset, Ollama allocates the
/// model's **full advertised window** — 131K or 262K — which took a 21 GB model to 29 GB resident;
/// capping to 16K recovered ~6 GB (ADR-009 Context). A silent default here would reintroduce a
/// measured trap, so the caller states the cap or does not get a request.
public struct ModelGenerationOptions: Equatable, Sendable {
    /// The model id to serve this request, resolved from a capability profile by configuration
    /// (NIC-243) — never hardcoded by a caller, per the standing rule that no named local model
    /// becomes an architectural dependency.
    public let modelID: String
    /// The context window to allocate, in tokens. See the type's note: this is a memory lever.
    public let contextTokens: Int
    public let temperature: Double
    /// Cap on generated tokens, or nil for the runtime's own limit.
    public let maxOutputTokens: Int?
    /// Whether the model may deliberate before answering. **Off by default**, matching the standing
    /// decision: composition from a typed snapshot is rendering, not reasoning, and leaving it on
    /// cost 3,000–4,200 tokens of deliberation before a short brief — 79–130 s against 9–17 s.
    public let thinking: Bool
    public let responseFormat: ModelResponseFormat
    /// How long the model stays resident afterwards.
    public let residency: ModelResidency
    /// Wall-clock budget for the whole request, enforced by ``ModelDeadline``. A stalled stream is
    /// not a slow stream: a transfer timeout alone cannot bound a runtime that accepts the request
    /// and then says nothing.
    public let timeout: Duration

    public init(
        modelID: String,
        contextTokens: Int,
        temperature: Double = 0,
        maxOutputTokens: Int? = nil,
        thinking: Bool = false,
        responseFormat: ModelResponseFormat = .text,
        // Ollama's own default is a five-minute idle window. Stated explicitly rather than
        // inherited silently, so residency is always something the code decided.
        residency: ModelResidency = .bounded(.seconds(300)),
        timeout: Duration = .seconds(120)
    ) {
        self.modelID = modelID
        self.contextTokens = contextTokens
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.thinking = thinking
        self.responseFormat = responseFormat
        self.residency = residency
        self.timeout = timeout
    }
}

/// One completion request: the transcript, the tools the model may propose, and the options.
///
/// `tools` being empty is the normal case for the passive tier, which composes prose and proposals
/// and calls nothing (decision 9). Note that each distinct tool set is a distinct prefix-cache
/// prefix — steady state measured 98.7% cached, turning ~46 s of cold prefill into ~1.5 s — so
/// callers should reuse a small, stable set rather than assembling one per request.
public struct ModelRequest: Equatable, Sendable {
    public let messages: [ModelMessage]
    public let tools: [ModelToolDefinition]
    public let options: ModelGenerationOptions

    public init(
        messages: [ModelMessage],
        tools: [ModelToolDefinition] = [],
        options: ModelGenerationOptions
    ) {
        self.messages = messages
        self.tools = tools
        self.options = options
    }
}
