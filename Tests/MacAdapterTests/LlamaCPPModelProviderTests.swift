// llama.cpp request building, SSE parsing, tool-call assembly, and error mapping.
//
// The offline tests below cover the pure helpers and run everywhere the macOS target builds.
//
// OPT-IN (CEREBRAL_LLAMACPP_TESTS=1): one live test streams a real completion. Gated because it
// needs `llama-server` running with a model loaded — an unreasonable thing to do inside an
// ordinary `swift test`. Run it deliberately:
//     CEREBRAL_LLAMACPP_TESTS=1 swift test --filter LlamaCPPModelProvider
#if canImport(AppKit)
import Foundation
import Testing
@testable import CerebralCore
@testable import CerebralMacAdapters

private func options(
    thinking: Bool = false,
    maxOutputTokens: Int? = nil,
    responseFormat: ModelResponseFormat = .text
) -> ModelGenerationOptions {
    ModelGenerationOptions(
        modelID: "qwen36-gguf",
        contextTokens: 16384,
        temperature: 0,
        maxOutputTokens: maxOutputTokens,
        thinking: thinking,
        responseFormat: responseFormat
    )
}

private func body(_ request: URLRequest) throws -> [String: Any] {
    // Deliberately not one nested expression: `#require` inside `#require` is a recursive macro
    // expansion and does not compile.
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

// MARK: - SSE framing

@Test("an SSE data line yields its payload; framing and keep-alives yield nothing")
func ssePayloadExtraction() {
    #expect(LlamaCPPModelProvider.ssePayload("data: {\"a\":1}") == "{\"a\":1}")
    // No space after the colon is legal SSE.
    #expect(LlamaCPPModelProvider.ssePayload("data:{\"a\":1}") == "{\"a\":1}")
    #expect(LlamaCPPModelProvider.ssePayload("data: [DONE]") == "[DONE]")
    #expect(LlamaCPPModelProvider.ssePayload("") == nil)
    #expect(LlamaCPPModelProvider.ssePayload(": keep-alive") == nil)
    #expect(LlamaCPPModelProvider.ssePayload("event: message") == nil)
}

// MARK: - The terminal chunk

@Test("the terminal chunk carries usage with an EMPTY choices array")
func terminalChunkHasNoChoices() throws {
    // Verified against b10330. Indexing `choices[0]` here is a crash on precisely the chunk that
    // carries the accounting, which is why the adapter guards rather than indexes.
    let payload = """
    {"choices":[],"created":1,"id":"x","model":"m","object":"chat.completion.chunk",\
    "usage":{"completion_tokens":8,"prompt_tokens":17,"total_tokens":25},\
    "timings":{"prompt_n":17,"prompt_per_second":125.3,"predicted_n":8,"predicted_per_second":45.2}}
    """
    let chunk = try LlamaCPPModelProvider.parse(payload: payload)
    #expect(chunk.choices?.isEmpty == true)
    #expect(chunk.usage?.completionTokens == 8)
    #expect(chunk.timings?.predictedPerSecond == 45.2)

    let usage = LlamaCPPModelProvider.usage(
        try #require(chunk.usage), timings: chunk.timings, wallDuration: .milliseconds(500)
    )
    #expect(usage.promptTokens == 17)
    #expect(usage.outputTokens == 8)
    #expect(usage.decodeTokensPerSecond == 45.2)
}

// MARK: - Tool-call assembly

@Test("tool-call argument fragments accumulate into one complete call")
func toolCallFragmentsAccumulate() throws {
    // The real fragmentation observed on the wire: `{`, `"title":"`, `Stand`, `up`, `"`, `}`.
    var pending = LlamaCPPModelProvider.PendingToolCall()
    pending.id = "call_1"
    pending.name = "note.capture"
    for fragment in ["{", "\"title\":\"", "Stand", "up", "\"", "}"] {
        pending.arguments += fragment
    }

    let call = try #require(pending.resolved())
    #expect(call.name == "note.capture")
    #expect(call.id == "call_1")
    #expect(call.arguments == .object(["title": .string("Standup")]))
}

@Test("a fragment stream that never names a tool resolves to nothing")
func namelessToolCallIsDropped() {
    var pending = LlamaCPPModelProvider.PendingToolCall()
    pending.arguments = "{}"
    #expect(pending.resolved() == nil)
}

@Test("unparseable arguments become an empty object rather than dropping the call")
func truncatedArgumentsSurviveAsEmpty() throws {
    // A truncated stream leaves half a JSON object. The port says a malformed proposal is a
    // finding for the caller, and the registry validates against the tool's schema regardless —
    // so losing the fact that the model tried to call the tool would be the worse outcome.
    var pending = LlamaCPPModelProvider.PendingToolCall()
    pending.name = "note.capture"
    pending.arguments = "{\"title\":\"Stand"

    let call = try #require(pending.resolved())
    #expect(call.name == "note.capture")
    #expect(call.arguments == .object([:]))
}

@Test("a streamed fragment decodes with its index and partial function")
func toolCallFragmentShape() throws {
    let payload = """
    {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"title\\":\\""}}]}}]}
    """
    let chunk = try LlamaCPPModelProvider.parse(payload: payload)
    let fragment = try #require(chunk.choices?.first?.delta?.toolCalls?.first)
    #expect(fragment.index == 0)
    #expect(fragment.id == nil)
    #expect(fragment.function?.name == nil)
    #expect(fragment.function?.arguments == "\"title\":\"")
}

// MARK: - Request building

@Test("thinking is toggled by the template kwarg, never by reasoning_budget")
func thinkingUsesTemplateKwarg() throws {
    // Probed: `reasoning_budget: 0` leaves reasoning ON (173 tokens, reasoning emitted) despite
    // being documented as "0 for immediate end". Only the template kwarg disables it.
    for thinking in [true, false] {
        let request = try LlamaCPPModelProvider.makeChatRequest(
            host: "http://localhost:8080",
            request: ModelRequest(messages: [.user("hi")], options: options(thinking: thinking))
        )
        let payload = try body(request)
        let kwargs = try #require(payload["chat_template_kwargs"] as? [String: Any])
        #expect(kwargs["enable_thinking"] as? Bool == thinking)
        #expect(payload["reasoning_budget"] == nil)
    }
}

@Test("a request always asks for usage, or the port's completed event has no cost to carry")
func requestAlwaysIncludesUsage() throws {
    let request = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(messages: [.user("hi")], options: options())
    )
    let payload = try body(request)
    #expect(payload["stream"] as? Bool == true)
    let streamOptions = try #require(payload["stream_options"] as? [String: Any])
    #expect(streamOptions["include_usage"] as? Bool == true)
}

@Test("a JSON-schema response format rides as a strict json_schema block")
func responseSchemaIsStrict() throws {
    let schema = JSONValue.object(["type": .string("object")])
    let request = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(
            messages: [.user("hi")],
            options: options(responseFormat: .jsonSchema(schema))
        )
    )
    let payload = try body(request)
    let format = try #require(payload["response_format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")
    let jsonSchema = try #require(format["json_schema"] as? [String: Any])
    // `strict` is what makes the schema a guarantee rather than a hint.
    #expect(jsonSchema["strict"] as? Bool == true)
    #expect(jsonSchema["schema"] as? [String: Any] != nil)
}

@Test("maxOutputTokens rides as max_tokens, and is absent when unset")
func maxTokensIsForwarded() throws {
    // Load-bearing for a grammar-constrained caller: an under-constrained schema will otherwise
    // emit valid output until the context runs out.
    let capped = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(messages: [.user("hi")], options: options(maxOutputTokens: 512))
    )
    #expect(try body(capped)["max_tokens"] as? Int == 512)

    let uncapped = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(messages: [.user("hi")], options: options())
    )
    #expect(try body(uncapped)["max_tokens"] == nil)
}

@Test("a tool result is keyed by tool_call_id, not by name")
func toolResultUsesCallID() throws {
    let request = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(
            messages: [
                .user("find my notes"),
                .assistant("", toolCalls: [
                    ModelToolCall(id: "call_1", name: "note.search", arguments: .object([:])),
                ]),
                .toolResult("{}", toolName: "note.search", toolCallID: "call_1"),
            ],
            options: options()
        )
    )
    let messages = try #require(try body(request)["messages"] as? [[String: Any]])
    let toolTurn = try #require(messages.last)
    #expect(toolTurn["role"] as? String == "tool")
    #expect(toolTurn["tool_call_id"] as? String == "call_1")
    // Ollama keys these by name; this runtime does not, and sending a name would not correlate.
    #expect(toolTurn["name"] == nil)
}

@Test("assistant tool calls encode their arguments as a STRING")
func assistantToolCallArgumentsAreAString() throws {
    let request = try LlamaCPPModelProvider.makeChatRequest(
        host: "http://localhost:8080",
        request: ModelRequest(
            messages: [
                .assistant("", toolCalls: [
                    ModelToolCall(id: "call_1", name: "note.capture", arguments: .object([
                        "title": .string("Standup"),
                    ])),
                ]),
            ],
            options: options()
        )
    )
    let messages = try #require(try body(request)["messages"] as? [[String: Any]])
    let calls = try #require(messages.first?["tool_calls"] as? [[String: Any]])
    let function = try #require(calls.first?["function"] as? [String: Any])
    // An object here would be Ollama's shape and is rejected by this API.
    #expect(function["arguments"] as? String == "{\"title\":\"Standup\"}")
}

// MARK: - Capabilities and readiness

@Test("this runtime is the one that ENFORCES a response schema")
func capabilitiesClaimEnforcement() async throws {
    let capabilities = try await LlamaCPPModelProvider().capabilities()
    #expect(capabilities.runtime == .llamaCPP)
    // The distinction the port exists to express, and the whole point of this adapter.
    #expect(capabilities.supportsResponseSchema)
    #expect(capabilities.enforcesResponseSchema)
    #expect(capabilities.supportsToolCalls)
}

@Test("the served model list is read from /v1/models")
func servedModelDecoding() throws {
    let data = Data(#"{"object":"list","data":[{"id":"qwen36-gguf","object":"model"}]}"#.utf8)
    #expect(try LlamaCPPModelProvider.servedModelIDs(data) == ["qwen36-gguf"])
}

@Test("the served context window is read from /props")
func servedContextDecoding() throws {
    let data = Data(#"{"default_generation_settings":{"n_ctx":16384}}"#.utf8)
    #expect(try LlamaCPPModelProvider.servedContext(data) == 16384)
}

// MARK: - Errors

@Test("a 400 preserves the converter's own message verbatim")
func grammarRejectionIsReported() {
    // The message a caller most needs to see: this is a contract problem, not a runtime fault.
    let body = #"{"error":{"code":400,"message":"JSON schema conversion failed:\nPattern must start with '^' and end with '$'","type":"invalid_request_error"}}"#
    let error = LlamaCPPModelProvider.error(status: 400, body: body)
    guard case let .providerFailed(message) = error else {
        Issue.record("expected providerFailed, got \(error)")
        return
    }
    #expect(message.contains("Pattern must start with"))
}

@Test("a 404 maps to modelNotInstalled")
func missingModelMaps() {
    let body = #"{"error":{"code":404,"message":"model not found","type":"not_found_error"}}"#
    #expect(LlamaCPPModelProvider.error(status: 404, body: body) == .modelNotInstalled("model not found"))
}

@Test("transport failures map onto the port's taxonomy, not URLSession's")
func transportErrorsMap() {
    #expect(LlamaCPPModelProvider.mapped(URLError(.timedOut)) == .timedOut)
    #expect(LlamaCPPModelProvider.mapped(URLError(.cancelled)) == .cancelled)
    #expect(LlamaCPPModelProvider.mapped(CancellationError()) == .cancelled)
    guard case .unavailable = LlamaCPPModelProvider.mapped(URLError(.cannotConnectToHost)) else {
        Issue.record("a dead server should be unavailable, with operator guidance")
        return
    }
}

@Test("unload is a no-op because the memory is the process")
func unloadIsANoOp() async {
    // Asserting the contract holds rather than asserting nothing: a caller may call this freely.
    await LlamaCPPModelProvider().unload(modelID: "qwen36-gguf")
}

// MARK: - Live (opt-in)

@Test(
    "a live completion streams text and reports real token accounting",
    .enabled(if: ProcessInfo.processInfo.environment["CEREBRAL_LLAMACPP_TESTS"] == "1")
)
func liveCompletion() async throws {
    let provider = LlamaCPPModelProvider()
    let modelID = ProcessInfo.processInfo.environment["CEREBRAL_LLAMACPP_MODEL"] ?? "qwen36-gguf"

    guard case .ready = await provider.readiness(for: modelID) else {
        Issue.record("llama-server is not serving \(modelID)")
        return
    }

    let completion = try await provider.complete(ModelRequest(
        messages: [.user("Reply with the single word: ready")],
        options: ModelGenerationOptions(modelID: modelID, contextTokens: 16384, maxOutputTokens: 16)
    ))

    #expect(!completion.text.isEmpty)
    #expect((completion.usage.outputTokens ?? 0) > 0)
    #expect((completion.usage.promptTokens ?? 0) > 0)
}
#endif
