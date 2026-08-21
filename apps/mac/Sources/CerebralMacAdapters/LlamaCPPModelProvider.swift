// The llama.cpp concrete behind the model provider port (ADR-009).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Serves completions from a local `llama-server` through its OpenAI-compatible API.
///
/// Verified against llama.cpp build **b10330**. This is the runtime that actually *enforces* a
/// response schema: it compiles the schema to a GBNF grammar and masks invalid tokens at every
/// sampling step, so it reports ``ModelRuntimeCapabilities/enforcesResponseSchema`` as **true**
/// where the Ollama adapter honestly reports false. Measured over 18 compositions of the same
/// document: 0 schema-invalid against Ollama's 6 with the same schema supplied.
///
/// Four behaviours below were probed rather than assumed, and each would be a bug if guessed:
///
/// * **Tool-call arguments stream as incremental string FRAGMENTS**, keyed by `index` — `{`, then
///   `"title":"`, then `Stand`, then `up`. Ollama sends one complete call per chunk. The port
///   promises a *complete* proposal, so fragments are accumulated and emitted at the end.
/// * **The terminal chunk carries an EMPTY `choices` array** alongside `usage` and `timings`.
///   Indexing `choices[0]` unguarded crashes on precisely the chunk that carries the accounting.
/// * **Thinking is disabled by `chat_template_kwargs: {"enable_thinking": false}`, NOT by
///   `reasoning_budget: 0`** — despite the latter being documented as "0 for immediate end".
///   Probed: 173 completion tokens with reasoning still emitted, against 2 tokens and none.
/// * **A `pattern` must be fully anchored and must not use `\d`.** The schema-to-grammar
///   converter rejects `^https://` outright and fails to compile `\d` in any form; `[0-9]` works.
///   Two shipped schemas had to be repaired before the tool manifest would compile at all.
///
/// Unlike Ollama this serves **one model per process** and ignores the `model` field, so
/// ``readiness(for:)`` compares against what the server reports rather than trusting the caller.
/// Context is a launch flag (`-c`), not a per-request option — see ``readiness(for:)``.
///
/// Nothing composes this into the live runtime. The first caller is the passive-tier composer,
/// and when it lands it **must** set ``ModelGenerationOptions/maxOutputTokens``: a grammar over an
/// under-constrained schema will emit valid output forever, measured at 123 blocks and 15,655
/// tokens before the context ran out and the document truncated mid-token.
public struct LlamaCPPModelProvider: ModelProvider {
    public let runtime = ModelRuntimeIdentifier.llamaCPP
    private let session: URLSession
    private let host: String

    /// llama.cpp's own convention: `LLAMA_HOST` when set, otherwise its loopback default.
    public static var defaultHost: String {
        ProcessInfo.processInfo.environment["LLAMA_HOST"] ?? "http://localhost:8080"
    }

    public init(
        session: URLSession? = nil,
        host: String = LlamaCPPModelProvider.defaultHost,
        // Same reasoning as the Ollama adapter: the real budget is the per-request deadline in
        // `ModelGenerationOptions.timeout`. These only stop a genuinely dead socket, and a cold
        // model load is minutes of silence for a 22 GB file.
        requestTimeout: TimeInterval = 300,
        resourceTimeout: TimeInterval = 900
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
    }

    // MARK: - ModelProvider

    public func capabilities() async throws -> ModelRuntimeCapabilities {
        ModelRuntimeCapabilities(
            runtime: .llamaCPP,
            supportsToolCalls: true,
            supportsThinkingToggle: true,
            supportsResponseSchema: true,
            // The distinction the port exists to express. Measured, not claimed: told explicitly
            // to emit the number zero against a string-typed field, the grammar forced a string.
            enforcesResponseSchema: true,
            supportsVision: false,
            maximumContextTokens: nil
        )
    }

    /// Whether this server can serve `modelID` right now.
    ///
    /// Two checks, because this runtime fails silently in two ways the Ollama one cannot. It
    /// **ignores the `model` field in a request**, so a mismatched id would quietly be served by
    /// whatever is loaded; and its context is fixed at launch by `-c`, so a caller asking for more
    /// than the server allocated gets a truncated prompt rather than an error.
    public func readiness(for modelID: String) async -> ModelReadiness {
        guard let url = URL(string: "\(host)/v1/models") else {
            return .unavailable("The configured llama.cpp host is not a valid URL.")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unavailable("llama.cpp responded, but not with its model list.")
            }
            let served = try Self.servedModelIDs(data)
            return served.contains(modelID) ? .ready : .modelNotInstalled(available: served)
        } catch {
            return .unavailable(
                "Cannot reach llama.cpp at \(host). Start it with: llama-server -hf <repo>:<quant> -c <tokens> -a \(modelID)"
            )
        }
    }

    /// The context window this server actually allocated, when it will say.
    ///
    /// Separate from ``capabilities()`` because it is a property of the running process rather
    /// than the runtime. A caller that needs a specific window must check this: `contextTokens`
    /// on a request cannot change it, and a silently smaller window is the difference between a
    /// measurement and a fiction.
    public func servedContextTokens() async -> Int? {
        guard let url = URL(string: "\(host)/props"),
              let (data, _) = try? await session.data(from: url) else { return nil }
        return try? Self.servedContext(data)
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await ModelDeadline.run(timeout: request.options.timeout) {
                        try await send(request, to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A no-op: with llama.cpp the memory IS the process.
    ///
    /// Present because the port promises the lever, and best-effort is the contract — a runtime
    /// that cannot evict on demand is not a failed request. Freeing this model means stopping the
    /// server, which is an operator action and deliberately not something an adapter does.
    public func unload(modelID: String) async {}

    // MARK: - The streaming turn

    private func send(
        _ request: ModelRequest,
        to continuation: AsyncThrowingStream<ModelStreamEvent, any Error>.Continuation
    ) async throws {
        let started = ContinuousClock.now
        let urlRequest = try Self.makeChatRequest(host: host, request: request)
        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.providerFailed("llama.cpp returned a response of an unknown kind.")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw Self.error(status: http.statusCode, body: body)
        }

        // Tool-call arguments arrive as fragments across chunks, so they are accumulated here and
        // emitted once the stream completes. Ordered by the wire's own `index`.
        var pendingCalls: [Int: PendingToolCall] = [:]

        for try await line in bytes.lines {
            guard let payload = Self.ssePayload(line) else { continue }
            if payload == Self.doneSentinel { break }

            let chunk = try Self.parse(payload: payload)
            if let error = chunk.error?.message {
                throw ModelProviderError.providerFailed(error)
            }

            // `choices` is EMPTY on the terminal usage chunk — verified. Guarding rather than
            // indexing is what keeps the accounting chunk from crashing the stream.
            if let delta = chunk.choices?.first?.delta {
                if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                    continuation.yield(.thinkingDelta(reasoning))
                }
                if let content = delta.content, !content.isEmpty {
                    continuation.yield(.textDelta(content))
                }
                for fragment in delta.toolCalls ?? [] {
                    var pending = pendingCalls[fragment.index] ?? PendingToolCall()
                    if let id = fragment.id { pending.id = id }
                    if let name = fragment.function?.name { pending.name = name }
                    if let arguments = fragment.function?.arguments { pending.arguments += arguments }
                    pendingCalls[fragment.index] = pending
                }
            }

            if let usage = chunk.usage {
                for index in pendingCalls.keys.sorted() {
                    if let call = pendingCalls[index]?.resolved() { continuation.yield(.toolCall(call)) }
                }
                pendingCalls.removeAll()
                continuation.yield(.completed(Self.usage(
                    usage, timings: chunk.timings, wallDuration: started.duration(to: .now)
                )))
            }
        }

        // A stream that ended without a usage chunk still owes its calls; the collector treats a
        // missing `completed` as a broken stream, which is the correct verdict on its own.
        for index in pendingCalls.keys.sorted() {
            if let call = pendingCalls[index]?.resolved() { continuation.yield(.toolCall(call)) }
        }
    }

    // MARK: - Pure helpers (unit-tested)

    static let doneSentinel = "[DONE]"

    /// The JSON payload of one Server-Sent Events line, or nil for framing and keep-alives.
    static func ssePayload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }

    /// Builds the streaming chat request.
    static func makeChatRequest(host: String, request: ModelRequest) throws -> URLRequest {
        guard let url = URL(string: "\(host)/v1/chat/completions") else {
            throw ModelProviderError.unavailable("The configured llama.cpp host is not a valid URL.")
        }
        let options = request.options

        var payload: [String: Any] = [
            // Sent for the record even though this runtime ignores it; `readiness(for:)` is what
            // actually establishes that the right model is loaded.
            "model": options.modelID,
            "messages": request.messages.map(Self.wireMessage),
            "stream": true,
            // Without this the terminal chunk carries no `usage`, and the port promises exactly
            // one `.completed` event carrying the cost.
            "stream_options": ["include_usage": true],
            "temperature": options.temperature,
            // NOT `reasoning_budget: 0` — see the type's note. That flag leaves reasoning on.
            "chat_template_kwargs": ["enable_thinking": options.thinking],
        ]
        if let maxOutputTokens = options.maxOutputTokens {
            payload["max_tokens"] = maxOutputTokens
        }

        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.anyValue,
                    ],
                ]
            }
        }

        if case let .jsonSchema(schema) = options.responseFormat {
            // Compiled to a grammar and enforced token by token — unlike the Ollama adapter's
            // best-effort `format:`. `strict` is what makes that a guarantee rather than a hint.
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "response", "schema": schema.anyValue, "strict": true],
            ]
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return urlRequest
    }

    /// One transcript turn in OpenAI shape.
    ///
    /// A `tool` turn is keyed by `tool_call_id`, not by name as Ollama does. A result the runtime
    /// cannot correlate is one the model re-requests, which reads as a runaway loop.
    static func wireMessage(_ message: ModelMessage) -> [String: Any] {
        var wire: [String: Any] = ["role": message.role.rawValue, "content": message.content]
        if message.role == .tool, let id = message.toolCallID {
            wire["tool_call_id"] = id
        }
        if !message.toolCalls.isEmpty {
            wire["tool_calls"] = message.toolCalls.enumerated().map { index, call in
                [
                    "index": index,
                    "id": call.id ?? "call_\(index)",
                    "type": "function",
                    "function": [
                        "name": call.name,
                        // Arguments ride as a STRING here, unlike Ollama's object.
                        "arguments": Self.encodedArguments(call.arguments),
                    ],
                ]
            }
        }
        return wire
    }

    static func encodedArguments(_ arguments: JSONValue) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: arguments.anyValue, options: [.sortedKeys, .fragmentsAllowed]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(payload: String) throws -> Chunk {
        do {
            return try Self.decoder.decode(Chunk.self, from: Data(payload.utf8))
        } catch {
            throw ModelProviderError.decodeFailed("A streamed chunk did not match llama.cpp's shape.")
        }
    }

    static func usage(_ usage: Usage, timings: Timings?, wallDuration: Duration) -> ModelUsage {
        ModelUsage(
            promptTokens: usage.promptTokens,
            outputTokens: usage.completionTokens,
            // Reported directly by the server rather than derived from durations, which is why
            // these do not go through `ModelUsage.rate`.
            prefillTokensPerSecond: timings?.promptPerSecond,
            decodeTokensPerSecond: timings?.predictedPerSecond,
            wallDuration: wallDuration
        )
    }

    static func servedModelIDs(_ data: Data) throws -> [String] {
        struct Models: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        do {
            return try JSONDecoder().decode(Models.self, from: data).data.map(\.id)
        } catch {
            throw ModelProviderError.decodeFailed("llama.cpp's model list did not match its shape.")
        }
    }

    static func servedContext(_ data: Data) throws -> Int {
        struct Props: Decodable {
            struct Settings: Decodable { let nCtx: Int? }
            let defaultGenerationSettings: Settings?
        }
        guard let context = try Self.decoder.decode(Props.self, from: data).defaultGenerationSettings?.nCtx else {
            throw ModelProviderError.decodeFailed("llama.cpp did not report a context size.")
        }
        return context
    }

    /// Maps a non-2xx response.
    ///
    /// A 400 here is usually not a bad request in the ordinary sense — it is the schema-to-grammar
    /// converter refusing to compile, which is a developer-facing contract problem rather than a
    /// runtime failure, so the reported message is preserved verbatim.
    static func error(status: Int, body: String) -> ModelProviderError {
        let reported = (try? Self.decoder.decode(ErrorEnvelope.self, from: Data(body.utf8)))?.error.message
        switch status {
        case 404:
            return .modelNotInstalled(reported ?? "llama.cpp is not serving that model.")
        case 400:
            return .providerFailed(reported ?? "llama.cpp rejected the request.")
        default:
            return .providerFailed(reported ?? "llama.cpp returned status \(status).")
        }
    }

    static func mapped(_ error: any Error) -> ModelProviderError {
        if let modelError = error as? ModelProviderError { return modelError }
        if error is CancellationError { return .cancelled }
        let urlError = error as? URLError
        switch urlError?.code {
        case .some(.cancelled):
            return .cancelled
        case .some(.timedOut):
            return .timedOut
        case .some(.cannotConnectToHost), .some(.cannotFindHost), .some(.networkConnectionLost):
            return .unavailable("Cannot reach llama.cpp. Start it with: llama-server -hf <repo>:<quant>")
        default:
            return .providerFailed(error.localizedDescription)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - Wire shapes

    /// A tool call under construction, assembled from fragments.
    struct PendingToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""

        /// The finished call, or nil if it never named a tool.
        ///
        /// Unparseable arguments become an empty object rather than dropping the call: the port
        /// says an unknown or malformed proposal is a finding for the caller, and the registry
        /// validates arguments against the tool's own schema anyway.
        func resolved() -> ModelToolCall? {
            guard let name else { return nil }
            let parsed = (try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8)))
                ?? .object([:])
            return ModelToolCall(id: id, name: name, arguments: parsed)
        }
    }

    struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
    }

    struct Timings: Decodable {
        let promptPerSecond: Double?
        let predictedPerSecond: Double?
    }

    /// One streamed chunk. Every field is optional: a chunk carries a delta, or the terminal
    /// accounting with an EMPTY `choices` array, never both.
    struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?
                let toolCalls: [ToolCallFragment]?
            }
            let delta: Delta?
            let finishReason: String?
        }

        struct ToolCallFragment: Decodable {
            struct Function: Decodable {
                let name: String?
                /// A FRAGMENT of the argument JSON, not the whole of it.
                let arguments: String?
            }
            let index: Int
            let id: String?
            let function: Function?
        }

        let choices: [Choice]?
        let usage: Usage?
        let timings: Timings?
        let error: ErrorEnvelope.Body?
    }
}
#endif
