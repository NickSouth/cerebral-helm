// NIC-242: the Ollama concrete behind the model provider port (ADR-009).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Serves completions from a local Ollama runtime through `POST /api/chat`.
///
/// Verified against **Ollama 0.32.7** on this machine, which serves models through its MLX engine
/// on Apple Silicon. Everything below that looks like a magic number was measured rather than
/// assumed:
///
/// * `keep_alive: -1` keeps a model resident indefinitely (probed: expiry reported as year 2318),
///   `0` unloads immediately (`done_reason: "unload"`), and a positive integer is seconds.
/// * An unknown model is **HTTP 404** with `{"error": "model '…' not found"}`, so it becomes
///   ``ModelProviderError/modelNotInstalled(_:)`` rather than a generic failure.
/// * Streaming is newline-delimited JSON; the terminal chunk carries `done: true` plus
///   `prompt_eval_count`, `eval_count`, and nanosecond durations — the token accounting.
///
/// It reports ``ModelRuntimeCapabilities/enforcesResponseSchema`` as **false**, which is the
/// honest answer: under `format: <schema>` this runtime still emitted `value: 0` where a string
/// was required. Callers needing guaranteed-valid structured output must wait for
/// grammar-constrained decoding (NIC-249), and the capability flag is how they find that out.
///
/// Nothing composes this provider into the live runtime. Phase 0 builds the seam; the first caller
/// is the passive-tier composer (NIC-250).
public struct OllamaModelProvider: ModelProvider {
    public let runtime = ModelRuntimeIdentifier.ollama
    private let session: URLSession
    private let host: String

    /// The runtime's own convention: `OLLAMA_HOST` when set, otherwise the loopback default.
    public static var defaultHost: String {
        ProcessInfo.processInfo.environment["OLLAMA_HOST"] ?? "http://localhost:11434"
    }

    public init(
        session: URLSession? = nil,
        host: String = OllamaModelProvider.defaultHost,
        // Generous on purpose, because the real budget is the per-request deadline in
        // `ModelGenerationOptions.timeout`, enforced by `ModelDeadline`. These only stop a
        // genuinely dead socket. `timeoutIntervalForRequest` is the *inactivity* window, and a
        // cold model load measured ~70 s of silence before the first token — the 60 s default
        // would kill exactly the request that needed patience.
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
            runtime: .ollama,
            supportsToolCalls: true,
            supportsThinkingToggle: true,
            supportsResponseSchema: true,
            // Measured, not assumed: `format:` is accepted and leaf types are not enforced.
            enforcesResponseSchema: false,
            // Text only today. Vision is the churn axis the port keeps room for, not a claim
            // about what this adapter does.
            supportsVision: false,
            maximumContextTokens: nil
        )
    }

    public func readiness(for modelID: String) async -> ModelReadiness {
        guard let url = URL(string: "\(host)/api/tags") else {
            return .unavailable("The configured Ollama host is not a valid URL.")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .unavailable("Ollama responded, but not with its model list.")
            }
            let installed = try Self.installedModelNames(data)
            return installed.contains(modelID)
                ? .ready
                : .modelNotInstalled(available: installed)
        } catch {
            // Actionable rather than a transport dump: the overwhelmingly common cause is that
            // the runtime simply is not running.
            return .unavailable("Cannot reach Ollama at \(host). Start it with: ollama serve")
        }
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

    public func unload(modelID: String) async {
        // The verified unload path is `/api/generate` with `keep_alive: 0`; the chat endpoint is
        // not a substitute here. Best-effort: a runtime that will not unload is not a failed
        // request, and this is called for its side effect only.
        guard let url = URL(string: "\(host)/api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["model": modelID, "keep_alive": 0]
        )
        _ = try? await session.data(for: request)
    }

    // MARK: - The streaming turn

    private func send(
        _ request: ModelRequest,
        to continuation: AsyncThrowingStream<ModelStreamEvent, any Error>.Continuation
    ) async throws {
        let started = ContinuousClock.now
        let urlRequest = try Self.makeChatRequest(host: host, request: request)
        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.providerFailed("Ollama returned a response of an unknown kind.")
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw Self.error(status: http.statusCode, body: body)
        }

        // `bytes.lines` performs the newline framing, including a chunk that splits mid-line —
        // the trap the JS harness had to hand-roll a tail buffer for.
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            let chunk = try Self.parse(line: line)

            if let error = chunk.error {
                throw ModelProviderError.providerFailed(error)
            }
            if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                continuation.yield(.thinkingDelta(thinking))
            }
            if let content = chunk.message?.content, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }
            for call in chunk.message?.toolCalls ?? [] {
                continuation.yield(.toolCall(ModelToolCall(
                    name: call.function.name,
                    arguments: call.function.arguments ?? .object([:])
                )))
            }
            if chunk.done == true {
                continuation.yield(.completed(Self.usage(chunk, wallDuration: started.duration(to: .now))))
            }
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds the streaming chat request.
    ///
    /// `num_ctx` is always sent. Omitting it is not a neutral default: this runtime then allocates
    /// the model's full advertised window (131K/262K), which took a 21 GB model to 29 GB resident.
    static func makeChatRequest(host: String, request: ModelRequest) throws -> URLRequest {
        guard let url = URL(string: "\(host)/api/chat") else {
            throw ModelProviderError.unavailable("The configured Ollama host is not a valid URL.")
        }
        let options = request.options

        var payload: [String: Any] = [
            "model": options.modelID,
            "messages": request.messages.map(Self.wireMessage),
            "stream": true,
            // Top-level, not inside `options` — this runtime reads it there.
            "think": options.thinking,
            "keep_alive": keepAlive(for: options.residency),
        ]

        var generation: [String: Any] = [
            "temperature": options.temperature,
            "num_ctx": options.contextTokens,
        ]
        if let maxOutputTokens = options.maxOutputTokens {
            generation["num_predict"] = maxOutputTokens
        }
        payload["options"] = generation

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
            // Best-effort: accepted, not enforced. See the type's note.
            payload["format"] = schema.anyValue
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return urlRequest
    }

    /// Residency as this runtime expresses it. Every value below was probed against 0.32.7:
    /// `-1` reported an expiry in the year 2318, `0` unloaded immediately, and a positive integer
    /// is an idle window in seconds.
    static func keepAlive(for residency: ModelResidency) -> Int {
        switch residency {
        case .pinned: return -1
        case .evictAfterUse: return 0
        case let .bounded(duration): return Int(duration.components.seconds)
        }
    }

    static func wireMessage(_ message: ModelMessage) -> [String: Any] {
        var wire: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content,
        ]
        if let toolName = message.toolName, message.role == .tool {
            wire["tool_name"] = toolName
        }
        if !message.toolCalls.isEmpty {
            wire["tool_calls"] = message.toolCalls.map { call in
                ["function": ["name": call.name, "arguments": call.arguments.anyValue]]
            }
        }
        return wire
    }

    static func parse(line: String) throws -> Chunk {
        guard let data = line.data(using: .utf8) else {
            throw ModelProviderError.decodeFailed("A streamed line was not valid UTF-8.")
        }
        do {
            return try Self.decoder.decode(Chunk.self, from: data)
        } catch {
            throw ModelProviderError.decodeFailed("A streamed chunk did not match Ollama's shape.")
        }
    }

    static func usage(_ chunk: Chunk, wallDuration: Duration) -> ModelUsage {
        ModelUsage(
            promptTokens: chunk.promptEvalCount,
            outputTokens: chunk.evalCount,
            prefillTokensPerSecond: ModelUsage.rate(
                tokens: chunk.promptEvalCount, nanoseconds: chunk.promptEvalDuration
            ),
            decodeTokensPerSecond: ModelUsage.rate(
                tokens: chunk.evalCount, nanoseconds: chunk.evalDuration
            ),
            wallDuration: wallDuration
        )
    }

    static func installedModelNames(_ data: Data) throws -> [String] {
        struct Tags: Decodable {
            struct Entry: Decodable { let name: String }
            let models: [Entry]
        }
        do {
            return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name)
        } catch {
            throw ModelProviderError.decodeFailed("Ollama's model list did not match its shape.")
        }
    }

    /// Maps a non-2xx response. A 404 is specifically "no such model" on this API — verified —
    /// so it becomes an error a caller can act on rather than a generic failure.
    static func error(status: Int, body: String) -> ModelProviderError {
        let reported = (try? Self.decoder.decode(ErrorBody.self, from: Data(body.utf8)))?.error
        switch status {
        case 404:
            return .modelNotInstalled(reported ?? "Ollama does not have that model.")
        default:
            return .providerFailed(reported ?? "Ollama returned status \(status).")
        }
    }

    /// Normalises everything the transport can throw into the port's taxonomy, so a caller never
    /// has to know what URLSession's error domains look like.
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
            return .unavailable("Cannot reach Ollama. Start it with: ollama serve")
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

    struct ErrorBody: Decodable {
        let error: String
    }

    /// One streamed chunk. Every field is optional because a chunk carries either a delta or the
    /// terminal accounting, never both in full — and because an `error` can arrive mid-stream.
    struct Chunk: Decodable {
        struct Message: Decodable {
            let content: String?
            let thinking: String?
            let toolCalls: [ToolCall]?
        }

        struct ToolCall: Decodable {
            struct Function: Decodable {
                let name: String
                let arguments: JSONValue?
            }
            let function: Function
        }

        let message: Message?
        let done: Bool?
        let error: String?
        let promptEvalCount: Int?
        let evalCount: Int?
        let promptEvalDuration: Int?
        let evalDuration: Int?
    }
}

// `JSONValue.anyValue` now lives in ModelWireValue.swift — every provider concrete needs it.
#endif
