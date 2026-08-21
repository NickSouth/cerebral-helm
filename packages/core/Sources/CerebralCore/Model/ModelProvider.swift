import Foundation

/// Which inference runtime is serving a model — Ollama, llama.cpp, MLX (NIC-241, ADR-009).
///
/// A string wrapper rather than a closed enum, for the same reason model ids come from
/// configuration: the landscape churns, and adding a runtime should not mean editing core. The
/// port names the **runtime**, not merely the model, because the difference that matters most —
/// whether invalid tool arguments are *impossible* (llama.cpp grammars) or merely unlikely — is a
/// property of the runtime, and it is still an open measurement (NIC-227).
public struct ModelRuntimeIdentifier: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let ollama = ModelRuntimeIdentifier(rawValue: "ollama")
    public static let llamaCPP = ModelRuntimeIdentifier(rawValue: "llama.cpp")
    public static let mlx = ModelRuntimeIdentifier(rawValue: "mlx")
}

/// What a runtime can actually do, so a caller can degrade honestly instead of assuming.
///
/// ``supportsResponseSchema`` and ``enforcesResponseSchema`` are separate on purpose, and the gap
/// between them is a measured one: Ollama accepts a schema and does not enforce leaf types. A
/// caller that needs guaranteed-valid structured output must check the second flag, not the first.
public struct ModelRuntimeCapabilities: Equatable, Sendable {
    public let runtime: ModelRuntimeIdentifier
    /// Whether the runtime can emit tool calls at all.
    public let supportsToolCalls: Bool
    /// Whether deliberation can be switched off per request.
    public let supportsThinkingToggle: Bool
    /// Whether the runtime accepts a response schema.
    public let supportsResponseSchema: Bool
    /// Whether it *enforces* that schema token by token. False for Ollama today; true is what
    /// grammar-constrained decoding buys (NIC-249).
    public let enforcesResponseSchema: Bool
    /// Text-only today. Vision is the third churn axis ADR-009 puts behind the port, needed for the
    /// North Star screen-context feature.
    public let supportsVision: Bool
    /// The largest context the runtime will serve, when it will say.
    public let maximumContextTokens: Int?

    public init(
        runtime: ModelRuntimeIdentifier,
        supportsToolCalls: Bool,
        supportsThinkingToggle: Bool,
        supportsResponseSchema: Bool,
        enforcesResponseSchema: Bool,
        supportsVision: Bool,
        maximumContextTokens: Int? = nil
    ) {
        self.runtime = runtime
        self.supportsToolCalls = supportsToolCalls
        self.supportsThinkingToggle = supportsThinkingToggle
        self.supportsResponseSchema = supportsResponseSchema
        self.enforcesResponseSchema = enforcesResponseSchema
        self.supportsVision = supportsVision
        self.maximumContextTokens = maximumContextTokens
    }
}

/// Whether a specific model can be served right now.
///
/// A probe, not a request: it answers "would this work" without spending a completion, and it does
/// not throw, because "the runtime is down" is an answer rather than a failure.
public enum ModelReadiness: Equatable, Sendable {
    case ready
    /// The runtime is reachable but does not have this model. Carries what it does have, so the
    /// caller can say something useful instead of "not found".
    case modelNotInstalled(available: [String])
    /// The runtime could not be reached. The string is operator-facing guidance.
    case unavailable(String)
}

/// One event from a streaming completion.
public enum ModelStreamEvent: Equatable, Sendable {
    /// A fragment of the answer.
    case textDelta(String)
    /// A fragment of the model's deliberation, when thinking is enabled. Emitted separately from
    /// ``textDelta(_:)`` so a renderer cannot show reasoning as the answer by accident.
    case thinkingDelta(String)
    /// A complete tool-call proposal. Never executed by this package.
    case toolCall(ModelToolCall)
    /// The terminal event. Exactly one is emitted on a successful stream, and it carries the cost.
    case completed(ModelUsage)
}

/// Why a completion could not be produced.
///
/// Coarse and provider-neutral, matching the convention every other port in this package follows:
/// a caller degrades honestly rather than branching on a runtime's error taxonomy.
public enum ModelProviderError: Error, Equatable, Sendable {
    /// The runtime could not be reached. The string is operator-facing guidance, e.g. how to start
    /// it — never a raw transport dump.
    case unavailable(String)
    /// The runtime is reachable but does not have the requested model.
    case modelNotInstalled(String)
    /// The request exceeded its wall-clock budget. See ``ModelDeadline``.
    case timedOut
    /// The caller cancelled. Distinct from a failure: nothing went wrong.
    case cancelled
    /// The prompt did not fit the allocated context window.
    case contextExceeded
    /// The runtime replied with something unparseable.
    case decodeFailed(String)
    /// Anything else the runtime reported.
    case providerFailed(String)
}

/// Races an operation against a wall-clock budget, failing with ``ModelProviderError/timedOut``.
///
/// Adapters use this rather than relying on transport timeouts alone: a resource timeout bounds a
/// slow transfer, but a runtime that accepts a request and then goes silent is neither slow nor
/// finished, and without a deadline it hangs the caller forever. Outer cancellation surfaces as
/// ``ModelProviderError/cancelled``, so callers see one error taxonomy rather than two.
public enum ModelDeadline {
    public static func run<T: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ModelProviderError.timedOut
                }
                // The first child to finish decides the outcome; the other is cancelled on the way
                // out and its result discarded.
                guard let first = try await group.next() else { throw ModelProviderError.timedOut }
                group.cancelAll()
                return first
            }
        } catch is CancellationError {
            throw ModelProviderError.cancelled
        }
    }
}

/// The one seam through which any model is reached (NIC-241, ADR-009).
///
/// Provider-neutral and portable: no concrete belongs in `packages/` — adapters live at the
/// application edge, and the first is the Ollama adapter in `apps/mac` (NIC-242). The port
/// produces text, tool-call *proposals*, and usage. It authorises nothing: risk classification and
/// confirmation policy stay deterministic and outside the model (ADR-003).
public protocol ModelProvider: Sendable {
    /// Which runtime this provider speaks to.
    var runtime: ModelRuntimeIdentifier { get }

    /// What the runtime can do. Async because a real adapter may have to ask it.
    func capabilities() async throws -> ModelRuntimeCapabilities

    /// Whether `modelID` can be served right now, without spending a completion.
    func readiness(for modelID: String) async -> ModelReadiness

    /// Stream a completion.
    ///
    /// The stream finishes after exactly one ``ModelStreamEvent/completed(_:)``, or terminates by
    /// throwing a ``ModelProviderError``. Cancelling the consuming task cancels the request and
    /// terminates the stream with ``ModelProviderError/cancelled``.
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error>

    /// Unload `modelID` immediately, releasing its memory.
    ///
    /// The lever behind ``ModelResidency/evictAfterUse``, and the one that keeps a rare specialist
    /// from holding tens of gigabytes against a surface someone is actually using. Best-effort: a
    /// runtime that cannot unload on demand is not a failed request.
    func unload(modelID: String) async
}

public extension ModelProvider {
    /// Collect a stream into one completion.
    ///
    /// Provided once, here, so the buffered and streaming paths cannot disagree about how deltas
    /// join or where usage comes from. The deadline is already carried by ``stream(_:)``, so this
    /// adds no second budget.
    func complete(_ request: ModelRequest) async throws -> ModelCompletion {
        var text = ""
        var thinking = ""
        var toolCalls: [ModelToolCall] = []
        var usage: ModelUsage?

        do {
            for try await event in stream(request) {
                switch event {
                case let .textDelta(delta): text += delta
                case let .thinkingDelta(delta): thinking += delta
                case let .toolCall(call): toolCalls.append(call)
                case let .completed(reported): usage = reported
                }
            }
        } catch is CancellationError {
            throw ModelProviderError.cancelled
        }

        // Cancelling a consumer *terminates* an `AsyncThrowingStream` rather than throwing through
        // it — verified, not assumed — so a cancelled request arrives here looking exactly like a
        // truncated one. Checking cancellation first is what keeps "the user changed their mind"
        // from being reported as "the runtime returned corruption".
        if Task.isCancelled { throw ModelProviderError.cancelled }

        // A stream that ended without its terminal event is a broken stream, not an empty answer.
        guard let usage else {
            throw ModelProviderError.decodeFailed("The stream ended without reporting completion.")
        }

        return ModelCompletion(
            text: text,
            thinking: thinking.isEmpty ? nil : thinking,
            toolCalls: toolCalls,
            usage: usage
        )
    }
}

/// A scripted ``ModelProvider`` for tests and for any build with no runtime attached: it ignores
/// the request and replays the events (or throws the error) it was constructed with.
///
/// Follows the fixed-outcome convention every other mock provider in this package uses. It does
/// not record what it was asked — a test that needs that declares its own recorder.
public struct MockModelProvider: ModelProvider {
    public let runtime: ModelRuntimeIdentifier
    private let outcome: Result<[ModelStreamEvent], ModelProviderError>
    private let runtimeCapabilities: ModelRuntimeCapabilities
    private let modelReadiness: ModelReadiness
    /// Delay before each event, so a test can force a timeout or observe cancellation mid-stream.
    private let delayPerEvent: Duration?

    public init(
        events: [ModelStreamEvent],
        runtime: ModelRuntimeIdentifier = ModelRuntimeIdentifier(rawValue: "mock"),
        capabilities: ModelRuntimeCapabilities? = nil,
        readiness: ModelReadiness = .ready,
        delayPerEvent: Duration? = nil
    ) {
        self.runtime = runtime
        self.outcome = .success(events)
        self.runtimeCapabilities = capabilities ?? Self.defaultCapabilities(runtime)
        self.modelReadiness = readiness
        self.delayPerEvent = delayPerEvent
    }

    public init(
        error: ModelProviderError,
        runtime: ModelRuntimeIdentifier = ModelRuntimeIdentifier(rawValue: "mock"),
        capabilities: ModelRuntimeCapabilities? = nil,
        readiness: ModelReadiness = .ready
    ) {
        self.runtime = runtime
        self.outcome = .failure(error)
        self.runtimeCapabilities = capabilities ?? Self.defaultCapabilities(runtime)
        self.modelReadiness = readiness
        self.delayPerEvent = nil
    }

    private static func defaultCapabilities(_ runtime: ModelRuntimeIdentifier) -> ModelRuntimeCapabilities {
        ModelRuntimeCapabilities(
            runtime: runtime,
            supportsToolCalls: true,
            supportsThinkingToggle: true,
            supportsResponseSchema: true,
            // The mock claims no enforcement, matching the only runtime measured so far. A test
            // that wants the guaranteed-output path says so explicitly.
            enforcesResponseSchema: false,
            supportsVision: false
        )
    }

    public func capabilities() async throws -> ModelRuntimeCapabilities { runtimeCapabilities }

    public func readiness(for modelID: String) async -> ModelReadiness { modelReadiness }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
        let outcome = outcome
        let delayPerEvent = delayPerEvent
        return AsyncThrowingStream { continuation in
            let task = Task {
                switch outcome {
                case let .failure(error):
                    continuation.finish(throwing: error)
                case let .success(events):
                    for event in events {
                        if let delayPerEvent {
                            do {
                                try await Task.sleep(for: delayPerEvent)
                            } catch {
                                continuation.finish(throwing: ModelProviderError.cancelled)
                                return
                            }
                        }
                        if Task.isCancelled {
                            continuation.finish(throwing: ModelProviderError.cancelled)
                            return
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func unload(modelID: String) async {}
}
