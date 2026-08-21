// NIC-242: Ollama request building, stream-chunk parsing, and error mapping.
//
// The offline tests below cover the pure helpers and run everywhere the macOS target builds.
//
// OPT-IN (CEREBRAL_OLLAMA_TESTS=1): one live test streams a real completion from a local runtime.
// It is gated because it needs `ollama serve` running and loads a ~21 GB model — an unreasonable
// thing to do inside an ordinary `swift test`. Run it deliberately:
//     CEREBRAL_OLLAMA_TESTS=1 swift test --filter OllamaModelProvider
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

private func options(
    modelID: String = "qwen3.6:35b-mlx",
    contextTokens: Int = 16_384,
    thinking: Bool = false,
    maxOutputTokens: Int? = nil,
    responseFormat: ModelResponseFormat = .text,
    residency: ModelResidency = .bounded(.seconds(300))
) -> ModelGenerationOptions {
    ModelGenerationOptions(
        modelID: modelID,
        contextTokens: contextTokens,
        temperature: 0.4,
        maxOutputTokens: maxOutputTokens,
        thinking: thinking,
        responseFormat: responseFormat,
        residency: residency
    )
}

private func body(_ request: ModelRequest) throws -> [String: Any] {
    let urlRequest = try OllamaModelProvider.makeChatRequest(host: "http://localhost:11434", request: request)
    let data = try #require(urlRequest.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

// MARK: - Request building

@Test("the request streams from /api/chat and always caps the context window")
func requestTargetsChatAndCapsContext() throws {
    let request = ModelRequest(messages: [.user("hello")], options: options())
    let urlRequest = try OllamaModelProvider.makeChatRequest(host: "http://localhost:11434", request: request)

    #expect(urlRequest.url?.absoluteString == "http://localhost:11434/api/chat")
    #expect(urlRequest.httpMethod == "POST")

    let payload = try body(request)
    #expect(payload["model"] as? String == "qwen3.6:35b-mlx")
    #expect(payload["stream"] as? Bool == true)

    // Omitting num_ctx is not a neutral default: this runtime then allocates the model's full
    // advertised window, which is how a 21 GB model became 29 GB resident.
    let generation = try #require(payload["options"] as? [String: Any])
    #expect(generation["num_ctx"] as? Int == 16_384)
    #expect(generation["temperature"] as? Double == 0.4)
    // No output cap was asked for, so none is sent — rather than a fabricated limit.
    #expect(generation["num_predict"] == nil)
}

@Test("thinking rides the top level, where this runtime reads it")
func thinkingIsTopLevel() throws {
    #expect(try body(ModelRequest(messages: [.user("hi")], options: options())) ["think"] as? Bool == false)
    #expect(try body(ModelRequest(messages: [.user("hi")], options: options(thinking: true)))["think"] as? Bool == true)
}

@Test("residency becomes the keep_alive value this runtime actually honours")
func residencyMapsToKeepAlive() throws {
    // Probed against Ollama 0.32.7: -1 reported an expiry in the year 2318, 0 unloaded
    // immediately (done_reason "unload"), and a positive integer is an idle window in seconds.
    #expect(OllamaModelProvider.keepAlive(for: .pinned) == -1)
    #expect(OllamaModelProvider.keepAlive(for: .evictAfterUse) == 0)
    #expect(OllamaModelProvider.keepAlive(for: .bounded(.seconds(300))) == 300)

    let pinned = try body(ModelRequest(messages: [.user("hi")], options: options(residency: .pinned)))
    #expect(pinned["keep_alive"] as? Int == -1)
}

@Test("an output cap is sent only when the caller asked for one")
func outputCapIsOptional() throws {
    let payload = try body(ModelRequest(messages: [.user("hi")], options: options(maxOutputTokens: 512)))
    let generation = try #require(payload["options"] as? [String: Any])
    #expect(generation["num_predict"] as? Int == 512)
}

@Test("a response schema is sent as format; plain text sends no format at all")
func responseFormatIsOptional() throws {
    #expect(try body(ModelRequest(messages: [.user("hi")], options: options()))["format"] == nil)

    let schema = JSONValue.object(["type": .string("object")])
    let payload = try body(ModelRequest(messages: [.user("hi")], options: options(responseFormat: .jsonSchema(schema))))
    let format = try #require(payload["format"] as? [String: Any])
    #expect(format["type"] as? String == "object")
}

@Test("tools are sent in this runtime's function shape, carrying no risk or policy metadata")
func toolsUseFunctionShape() throws {
    let tool = ModelToolDefinition(
        name: "note.capture",
        description: "Capture a note.",
        parameters: .object(["type": .string("object")])
    )
    let payload = try body(ModelRequest(messages: [.user("hi")], tools: [tool], options: options()))

    let tools = try #require(payload["tools"] as? [[String: Any]])
    #expect(tools.count == 1)
    #expect(tools[0]["type"] as? String == "function")
    let function = try #require(tools[0]["function"] as? [String: Any])
    #expect(function["name"] as? String == "note.capture")
    // Risk class and confirmation policy must never reach a model-facing manifest.
    #expect(function["risk"] == nil)
    #expect(function["requiresConfirmation"] == nil)
}

@Test("a tool result turn names the tool it answers")
func toolResultCarriesItsName() throws {
    let request = ModelRequest(
        messages: [.user("what's on today"), .toolResult("2 events", toolName: "calendar.list")],
        options: options()
    )
    let messages = try #require(try body(request)["messages"] as? [[String: Any]])
    #expect(messages[1]["role"] as? String == "tool")
    #expect(messages[1]["tool_name"] as? String == "calendar.list")
}

// MARK: - Stream chunk parsing

@Test("a content chunk parses its delta")
func parsesContentDelta() throws {
    let chunk = try OllamaModelProvider.parse(
        line: #"{"model":"m","message":{"role":"assistant","content":"Good "},"done":false}"#
    )
    #expect(chunk.message?.content == "Good ")
    #expect(chunk.done == false)
}

@Test("the terminal chunk carries the token accounting")
func parsesTerminalChunk() throws {
    let chunk = try OllamaModelProvider.parse(line: """
    {"model":"m","message":{"role":"assistant","content":""},"done":true,\
    "prompt_eval_count":4535,"prompt_eval_duration":5000000000,\
    "eval_count":120,"eval_duration":2000000000}
    """)
    #expect(chunk.done == true)

    let usage = OllamaModelProvider.usage(chunk, wallDuration: .seconds(8))
    #expect(usage.promptTokens == 4_535)
    #expect(usage.outputTokens == 120)
    #expect(usage.prefillTokensPerSecond == 907)   // 4535 tokens / 5s
    #expect(usage.decodeTokensPerSecond == 60)     // 120 tokens / 2s
    // Wall time is measured by the adapter, and includes a cold load the runtime's own timings
    // never show.
    #expect(usage.wallDuration == .seconds(8))
}

@Test("a terminal chunk with no counts reports no rates rather than zeroes")
func terminalChunkWithoutCounts() throws {
    let chunk = try OllamaModelProvider.parse(line: #"{"model":"m","done":true}"#)
    let usage = OllamaModelProvider.usage(chunk, wallDuration: .milliseconds(10))

    #expect(usage.promptTokens == nil)
    #expect(usage.decodeTokensPerSecond == nil)
}

@Test("a tool call parses its name and structural arguments")
func parsesToolCall() throws {
    let chunk = try OllamaModelProvider.parse(line: """
    {"model":"m","message":{"role":"assistant","content":"",\
    "tool_calls":[{"function":{"name":"note.capture","arguments":{"text":"buy milk","kind":"note"}}}]},"done":false}
    """)

    let call = try #require(chunk.message?.toolCalls?.first)
    #expect(call.function.name == "note.capture")
    #expect(call.function.arguments == .object(["text": .string("buy milk"), "kind": .string("note")]))
}

@Test("deliberation arrives in its own field, never folded into content")
func parsesThinking() throws {
    let chunk = try OllamaModelProvider.parse(
        line: #"{"model":"m","message":{"role":"assistant","content":"","thinking":"weighing it"},"done":false}"#
    )
    #expect(chunk.message?.thinking == "weighing it")
    #expect(chunk.message?.content == "")
}

@Test("an unparseable line fails as decodeFailed, never as a silent empty answer")
func malformedLineFails() {
    #expect(throws: ModelProviderError.decodeFailed("A streamed chunk did not match Ollama's shape.")) {
        _ = try OllamaModelProvider.parse(line: "{not json")
    }
}

// MARK: - Readiness and errors

@Test("the model list parses into installed names")
func parsesTags() throws {
    let data = Data(#"{"models":[{"name":"qwen3.6:35b-mlx"},{"name":"qwen3-embedding:0.6b"}]}"#.utf8)
    #expect(try OllamaModelProvider.installedModelNames(data) == ["qwen3.6:35b-mlx", "qwen3-embedding:0.6b"])
}

@Test("a 404 is 'no such model', not a generic failure")
func notFoundMeansModelMissing() {
    // The exact body this runtime returns, verified against 0.32.7.
    let error = OllamaModelProvider.error(status: 404, body: #"{"error":"model 'does-not-exist:9b' not found"}"#)
    #expect(error == .modelNotInstalled("model 'does-not-exist:9b' not found"))

    #expect(OllamaModelProvider.error(status: 500, body: #"{"error":"boom"}"#) == .providerFailed("boom"))
    // A body that is not the documented shape still yields something actionable.
    #expect(OllamaModelProvider.error(status: 503, body: "<html>") == .providerFailed("Ollama returned status 503."))
}

@Test("transport failures map onto the port's taxonomy, not URLSession's")
func transportErrorsAreNormalised() {
    #expect(OllamaModelProvider.mapped(URLError(.cancelled)) == .cancelled)
    #expect(OllamaModelProvider.mapped(URLError(.timedOut)) == .timedOut)
    #expect(OllamaModelProvider.mapped(URLError(.cannotConnectToHost)) == .unavailable("Cannot reach Ollama. Start it with: ollama serve"))
    #expect(OllamaModelProvider.mapped(CancellationError()) == .cancelled)
    // An error already in the taxonomy passes through untouched.
    #expect(OllamaModelProvider.mapped(ModelProviderError.timedOut) == .timedOut)
}

@Test("an unreachable runtime is reported with the command that fixes it")
func unreachableRuntimeGuidance() async {
    // Port 1 is reserved and never serves Ollama, so this exercises the real failure path.
    let provider = OllamaModelProvider(host: "http://127.0.0.1:1")
    let readiness = await provider.readiness(for: "qwen3.6:35b-mlx")

    guard case let .unavailable(guidance) = readiness else {
        Issue.record("Expected an unavailable runtime, got \(readiness)")
        return
    }
    #expect(guidance.contains("ollama serve"))
}

// MARK: - Live runtime (opt-in)

private var liveRuntimeRequested: Bool {
    ProcessInfo.processInfo.environment["CEREBRAL_OLLAMA_TESTS"] == "1"
}

private var liveModel: String {
    ProcessInfo.processInfo.environment["CEREBRAL_OLLAMA_TEST_MODEL"] ?? "qwen3.6:35b-mlx"
}

@Test("a real completion streams text and reports non-zero usage")
func liveCompletionStreams() async throws {
    guard liveRuntimeRequested else { return }

    let provider = OllamaModelProvider()
    guard case .ready = await provider.readiness(for: liveModel) else {
        Issue.record("\(liveModel) is not installed on this machine.")
        return
    }

    let request = ModelRequest(
        messages: [.system("Answer in exactly one short sentence."), .user("Name one colour.")],
        options: ModelGenerationOptions(
            modelID: liveModel,
            contextTokens: 4_096,
            maxOutputTokens: 64,
            // Unload afterwards: a test must not leave tens of gigabytes resident on the machine
            // it ran on.
            residency: .evictAfterUse,
            timeout: .seconds(300)
        )
    )

    let completion = try await provider.complete(request)

    #expect(!completion.text.isEmpty)
    #expect((completion.usage.outputTokens ?? 0) > 0)
    #expect((completion.usage.promptTokens ?? 0) > 0)
    // Thinking was off, so none should have been reported.
    #expect(completion.thinking == nil)

    await provider.unload(modelID: liveModel)
}
#endif
