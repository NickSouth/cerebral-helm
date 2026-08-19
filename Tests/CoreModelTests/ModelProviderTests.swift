import Foundation
import Testing

import CerebralCore

/// NIC-241: the model provider port.
///
/// Its guarantees are about **honesty under failure**: a stream that ends early is not an empty
/// answer, a cancelled request is not a failure, a stalled runtime cannot hang a caller forever,
/// and a rate that cannot be computed is not a rate of nought.

private func options(
    contextTokens: Int = 16_384,
    thinking: Bool = false,
    timeout: Duration = .seconds(120)
) -> ModelGenerationOptions {
    ModelGenerationOptions(
        modelID: "test-model",
        contextTokens: contextTokens,
        thinking: thinking,
        timeout: timeout
    )
}

private func request(_ text: String = "compose the brief") -> ModelRequest {
    ModelRequest(messages: [.system("you compose"), .user(text)], options: options())
}

private let noUsage = ModelUsage(wallDuration: .milliseconds(1))

// MARK: - Folding a stream into a completion

@Test("a streamed completion folds its deltas in order and carries usage")
func completeFoldsDeltas() async throws {
    let usage = ModelUsage(
        promptTokens: 4_535,
        outputTokens: 120,
        prefillTokensPerSecond: 900,
        decodeTokensPerSecond: 66.8,
        wallDuration: .seconds(3)
    )
    let provider = MockModelProvider(events: [
        .textDelta("Good "),
        .textDelta("morning"),
        .textDelta(", Nick."),
        .completed(usage),
    ])

    let completion = try await provider.complete(request())

    #expect(completion.text == "Good morning, Nick.")
    #expect(completion.thinking == nil)
    #expect(completion.toolCalls.isEmpty)
    #expect(completion.usage == usage)
}

@Test("deliberation is kept out of the answer, never concatenated into it")
func thinkingStaysSeparate() async throws {
    let provider = MockModelProvider(events: [
        .thinkingDelta("The user asked for "),
        .thinkingDelta("a brief, so..."),
        .textDelta("Three things today."),
        .completed(noUsage),
    ])

    let completion = try await provider.complete(request())

    #expect(completion.text == "Three things today.")
    #expect(completion.thinking == "The user asked for a brief, so...")
}

@Test("tool-call proposals accumulate in the order the model emitted them")
func toolCallsPreserveOrder() async throws {
    let first = ModelToolCall(name: "note.capture", arguments: .object(["text": .string("a")]))
    let second = ModelToolCall(id: "call_2", name: "calendar.list", arguments: .object([:]))
    let provider = MockModelProvider(events: [
        .toolCall(first),
        .toolCall(second),
        .completed(noUsage),
    ])

    let completion = try await provider.complete(request())

    #expect(completion.toolCalls == [first, second])
    // The port proposes; it never executes. Nothing here resolves, validates, or runs a tool.
    #expect(completion.text.isEmpty)
}

@Test("a stream that ends without its terminal event is a broken stream, not an empty answer")
func missingCompletionIsAFailure() async throws {
    let provider = MockModelProvider(events: [.textDelta("half an ans")])

    await #expect(throws: ModelProviderError.self) {
        _ = try await provider.complete(request())
    }
}

@Test("a provider failure reaches the caller unchanged")
func providerErrorPropagates() async throws {
    let provider = MockModelProvider(error: .unavailable("Cannot reach the runtime."))

    await #expect(throws: ModelProviderError.unavailable("Cannot reach the runtime.")) {
        _ = try await provider.complete(request())
    }
}

// MARK: - Cancellation

@Test("cancelling the caller stops the stream and reports cancellation, not failure")
func cancellationIsNotAFailure() async throws {
    let provider = MockModelProvider(
        events: [.textDelta("one"), .textDelta("two"), .textDelta("three"), .completed(noUsage)],
        delayPerEvent: .milliseconds(80)
    )

    let task = Task { try await provider.complete(request()) }
    try await Task.sleep(for: .milliseconds(40))
    task.cancel()

    await #expect(throws: ModelProviderError.cancelled) {
        _ = try await task.value
    }
}

// MARK: - Deadline

@Test("an operation inside its budget returns its value")
func deadlineAllowsFastWork() async throws {
    let value = try await ModelDeadline.run(timeout: .seconds(5)) { 42 }
    #expect(value == 42)
}

@Test("a stalled operation fails with timedOut rather than hanging the caller")
func deadlineFailsSlowWork() async throws {
    await #expect(throws: ModelProviderError.timedOut) {
        _ = try await ModelDeadline.run(timeout: .milliseconds(30)) {
            // The runtime that accepts a request and then says nothing: neither slow nor finished.
            try await Task.sleep(for: .seconds(30))
            return 0
        }
    }
}

@Test("cancelling a deadlined operation reports cancellation, not a timeout")
func deadlineReportsCancellationSeparately() async throws {
    let task = Task {
        try await ModelDeadline.run(timeout: .seconds(30)) {
            try await Task.sleep(for: .seconds(30))
            return 0
        }
    }
    try await Task.sleep(for: .milliseconds(30))
    task.cancel()

    await #expect(throws: ModelProviderError.cancelled) {
        _ = try await task.value
    }
}

// MARK: - Usage arithmetic

@Test("a rate is tokens over nanoseconds, and absent when it cannot be computed")
func rateArithmetic() {
    // 120 tokens in 2s → 60 tok/s.
    #expect(ModelUsage.rate(tokens: 120, nanoseconds: 2_000_000_000) == 60)
    // Missing or zero inputs yield no rate — never zero, never infinity.
    #expect(ModelUsage.rate(tokens: nil, nanoseconds: 2_000_000_000) == nil)
    #expect(ModelUsage.rate(tokens: 120, nanoseconds: nil) == nil)
    #expect(ModelUsage.rate(tokens: 0, nanoseconds: 2_000_000_000) == nil)
    #expect(ModelUsage.rate(tokens: 120, nanoseconds: 0) == nil)
}

// MARK: - The decisions the option defaults encode

@Test("thinking is off by default and residency is stated, not inherited")
func optionDefaultsEncodeTheDecisions() {
    let defaults = ModelGenerationOptions(modelID: "qwen3.6:35b-mlx", contextTokens: 16_384)

    // Decision 2: composition from a typed snapshot is rendering, not reasoning.
    #expect(defaults.thinking == false)
    // The runtime's own five-minute idle window, written down rather than assumed.
    #expect(defaults.residency == .bounded(.seconds(300)))
    #expect(defaults.temperature == 0)
    #expect(defaults.responseFormat == .text)
    // Context has no default at all: unset, a runtime allocates the full advertised window.
    #expect(defaults.contextTokens == 16_384)
}

@Test("a runtime that accepts a schema is not a runtime that enforces one")
func schemaSupportIsNotSchemaEnforcement() async throws {
    // The measured Ollama shape: `format:` accepted, leaf types unenforced.
    let provider = MockModelProvider(events: [.completed(noUsage)])
    let capabilities = try await provider.capabilities()

    #expect(capabilities.supportsResponseSchema)
    #expect(capabilities.enforcesResponseSchema == false)
    #expect(capabilities.supportsVision == false)
}

@Test("readiness answers without spending a completion")
func readinessIsAProbe() async {
    let missing = MockModelProvider(
        events: [],
        readiness: .modelNotInstalled(available: ["qwen3.6:35b-mlx"])
    )

    #expect(await missing.readiness(for: "muse-glimmer:30b-mlx") == .modelNotInstalled(available: ["qwen3.6:35b-mlx"]))
}
