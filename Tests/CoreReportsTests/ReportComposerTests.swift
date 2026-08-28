import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-250: the model as the Composer, behind the seam the deterministic formula already occupies.
///
/// Every test here drives `MockModelProvider`, so nothing depends on a runtime being installed.
/// What is worth protecting is not the happy path — it is the failures, because the whole reason
/// this type exists rather than a one-line `JSONDecoder` call is that a local model's answer is
/// wrong in specific, measured ways: a leaf typed as a string arriving as a number (6 of 6 runs of
/// one snapshot), a document that ran to the context wall and truncated mid-token, and a fenced
/// answer from a model told to reply with JSON and nothing else.

// MARK: - Fixtures

private func usage(outputTokens: Int? = 250) -> ModelUsage {
    ModelUsage(outputTokens: outputTokens, wallDuration: .seconds(9))
}

private func provider(
    text: String,
    outputTokens: Int? = 250
) -> MockModelProvider {
    MockModelProvider(events: [.textDelta(text), .completed(usage(outputTokens: outputTokens))])
}

/// A provider that answers differently on each call, so a retry can be observed.
private final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    let runtime = ModelRuntimeIdentifier(rawValue: "mock")
    private let answers: [String]
    private let lock = NSLock()
    private var index = 0
    /// Every request the composer made, so a test can assert the correction was actually sent.
    private(set) var requests: [ModelRequest] = []

    init(answers: [String]) {
        self.answers = answers
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    func recordedRequests() -> [ModelRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func capabilities() async throws -> ModelRuntimeCapabilities {
        ModelRuntimeCapabilities(
            runtime: runtime, supportsToolCalls: false, supportsThinkingToggle: true,
            supportsResponseSchema: false, enforcesResponseSchema: false, supportsVision: false
        )
    }

    func readiness(for modelID: String) async -> ModelReadiness { .ready }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, any Error> {
        lock.lock()
        let answer = index < answers.count ? answers[index] : answers[answers.count - 1]
        index += 1
        requests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(answer))
            continuation.yield(.completed(usage()))
            continuation.finish()
        }
    }

    func unload(modelID: String) async {}
}

private let profiles = ModelProfileCatalog(
    residentBudgetGigabytes: 48,
    resolutions: [
        ModelProfileResolution(
            profile: .local,
            modelID: "qwen3.6:35b-mlx",
            runtime: .ollama,
            contextTokens: 16_384,
            residency: .bounded(.seconds(300)),
            thinking: false,
            timeout: .seconds(120)
        )
    ]
)

private func composers(
    maxBlocks: Int = 12,
    maxOutputTokens: Int = 1200,
    profile: ModelProfileID = .local,
    discardsGreeting: Bool? = nil
) -> CerebralHelmModelComposerCatalog {
    CerebralHelmModelComposerCatalog(
        composerReports: [
            ComposerReport(
                composerDiscardsGreeting: discardsGreeting,
                composerInstruction: "Compile the morning brief.",
                composerMaxBlocks: maxBlocks,
                composerMaxOutputTokens: maxOutputTokens,
                composerReportID: "daily-brief",
                composerTemperature: 0.4,
                extensions: nil,
                modelProfileID: profile
            )
        ],
        composerSystemPrompt: "You compose CerebralHelm report documents.",
        extensions: nil,
        schemaVersion: "1.0.0"
    )
}

private func request() -> ReportCompositionRequest {
    ReportCompositionRequest(
        reportID: "daily-brief",
        snapshot: .object([
            "now": .string("2026-08-26T07:15:00-04:00"),
            "calendar": .array([])
        ])
    )
}

private func compose(
    _ provider: any ModelProvider,
    maxBlocks: Int = 12,
    maxOutputTokens: Int = 1200,
    profile: ModelProfileID = .local,
    discardsGreeting: Bool? = nil,
    onBlocks: (@Sendable ([Block]) -> Void)? = nil
) async -> ReportCompositionOutcome {
    await ReportComposer(
        provider: provider,
        profiles: profiles,
        composers: composers(
            maxBlocks: maxBlocks, maxOutputTokens: maxOutputTokens,
            profile: profile, discardsGreeting: discardsGreeting
        )
    ).compose(request(), onBlocks: onBlocks)
}

private let goodAnswer = """
{"blocks":[{"blockKind":"line","text":"Your calendar is clear.","lineEmphasis":"normal"}]}
"""

// MARK: - The envelope is the system's

@Test("the model writes blocks and the system writes the envelope")
func envelopeIsNotComposed() async throws {
    // The model's answer carries no `schemaVersion` and no `reportId` — it cannot, because it was
    // never asked for them. Every failure in the first spike was a malformed envelope field.
    guard case let .composed(report) = await compose(provider(text: goodAnswer)) else {
        Issue.record("A well-formed answer must compose.")
        return
    }

    #expect(report.document.schemaVersion == "1.0.0")
    #expect(report.document.reportID == "daily-brief")
    #expect(report.document.blocks.count == 1)
    #expect(report.document.blocks[0].text == "Your calendar is clear.")
    // Composed from an assembled snapshot, not from a repeatable fetch: offering a refresh would
    // promise something the document cannot do.
    #expect(report.document.refreshable == nil)
    #expect(report.attempts == 1)
}

@Test("the request carries the profile's own generation settings, deliberation off")
func requestUsesProfileSettings() async throws {
    let scripted = ScriptedProvider(answers: [goodAnswer])
    _ = await compose(scripted)

    let options = try #require(scripted.recordedRequests().first?.options)
    // AC-3. Composition from an already-typed snapshot is rendering, not reasoning: left to
    // deliberate, the model spent 3,000-4,200 tokens before emitting a short brief.
    #expect(options.thinking == false)
    // AC-11. Never nil: a composition with no ceiling ran to 15,655 tokens and truncated mid-token.
    #expect(options.maxOutputTokens == 1200)
    #expect(options.contextTokens == 16_384)
    #expect(options.temperature == 0.4)
    #expect(options.modelID == "qwen3.6:35b-mlx")
    // The passive tier calls nothing. An empty tool set is also one stable prefix-cache prefix.
    #expect(scripted.recordedRequests().first?.tools.isEmpty == true)
}

@Test("the snapshot reaches the model with its keys in a stable order")
func snapshotIsSerialisedDeterministically() async throws {
    let scripted = ScriptedProvider(answers: [goodAnswer])
    _ = await compose(scripted)

    let user = try #require(scripted.recordedRequests().first?.messages.last?.content)
    // Sorted keys, so the same snapshot produces the same prefix every time. Each distinct prefix
    // is a distinct prefix-cache entry, and steady state was measured at 98.7% cached.
    #expect(user.contains("{\"calendar\":[],\"now\":\"2026-08-26T07:15:00-04:00\"}"))
    #expect(user.contains("reportId: daily-brief"))
    #expect(user.contains("Compile the morning brief."))
}

// MARK: - The measured failures

@Test("a count block emitting a number where a string is required is rejected")
func leafTypeViolationIsRejected() async {
    // The exact failure measured on 6 of 6 runs of one snapshot, WITH the schema supplied to
    // Ollama. Decoding into the generated `Block` is what makes it impossible to render.
    let answer = """
    {"blocks":[{"blockKind":"count","value":0,"label":"unread"}]}
    """

    guard case let .failed(failure) = await compose(provider(text: answer)) else {
        Issue.record("A numeric `value` must not compose.")
        return
    }
    guard case let .invalid(reason, attempts) = failure else {
        Issue.record("A wrong leaf type is invalid, not \(failure).")
        return
    }
    #expect(reason.contains("value"))
    #expect(attempts == ReportComposer.maximumAttempts)
}

@Test("an invented block kind is rejected rather than rendered blank")
func unknownEnumCaseIsRejected() async {
    let answer = """
    {"blocks":[{"blockKind":"timeline","text":"Something."}]}
    """

    guard case let .failed(.invalid(reason, _)) = await compose(provider(text: answer)) else {
        Issue.record("An unknown block kind is invalid.")
        return
    }
    #expect(reason.contains("allowed values"))
}

@Test("a truncated document is reported as truncated, never as invalid")
func truncationIsDistinctFromInvalidity() async {
    // AC-12. A document cut off mid-token is UNPARSEABLE rather than wrong, and the two need
    // different recovery: this one means the budget was too small, not that the model
    // misunderstood. A caller that only validated against the schema could not tell them apart.
    let cutOff = """
    {"blocks":[{"blockKind":"line","text":"Your calendar is cle
    """

    guard case let .failed(failure) = await compose(provider(text: cutOff, outputTokens: 1200)) else {
        Issue.record("A cut-off document must not compose.")
        return
    }
    guard case .truncated = failure else {
        Issue.record("A cut-off document is truncated, not \(failure).")
        return
    }
}

@Test("spending the whole output budget marks a failure as truncation even mid-structure")
func truncationIsDetectedFromTheTokenBudget() {
    // Two independent signals, either sufficient: the budget was spent, or the body does not close
    // its own object. The second catches a runtime that stopped for its own reasons and reported
    // no token count at all.
    #expect(ReportComposer.looksTruncated("{\"blocks\":[", cap: 1200, usage: usage(outputTokens: 1200)))
    #expect(ReportComposer.looksTruncated("{\"blocks\":[", cap: 1200, usage: usage(outputTokens: nil)))
    #expect(!ReportComposer.looksTruncated("{\"blocks\":[]}", cap: 1200, usage: usage(outputTokens: 12)))
}

@Test("a runaway is stopped by the report's own block cap, not only by the contract's")
func blockCapIsEnforced() async {
    // One measured composition produced 123 blocks — `line`/`metric` alternating, every optional
    // field filled — until it exhausted the context. The contract's cap of 64 is the safety bound;
    // this report's cap of 12 is the editorial one, and it bites first.
    let many = (0..<20).map { "{\"blockKind\":\"line\",\"text\":\"Line \($0).\"}" }.joined(separator: ",")

    guard case let .failed(.invalid(reason, _)) = await compose(provider(text: "{\"blocks\":[\(many)]}")) else {
        Issue.record("Twenty blocks against a cap of twelve must not compose.")
        return
    }
    #expect(reason.contains("20 blocks"))
}

@Test("an over-long string is caught even though decoding accepts it")
func boundsAreCheckedBeyondDecoding() async {
    // `Codable` has no opinion about `maxLength`, so this decodes perfectly and still breaks the
    // contract the renderer's document is validated against downstream.
    let long = String(repeating: "a", count: ReportBlockBounds.text + 1)

    guard case let .failed(.invalid(reason, _)) = await compose(
        provider(text: "{\"blocks\":[{\"blockKind\":\"line\",\"text\":\"\(long)\"}]}")
    ) else {
        Issue.record("An over-long string must not compose.")
        return
    }
    #expect(reason.contains("/blocks/0/text"))
}

@Test("a document with no blocks is a failed composition, not an empty day")
func emptyDocumentIsRejected() async {
    // Schema-legal and still wrong. The snapshot being empty is something the model is told to
    // SAY; answering with silence would render as a blank body beneath a deterministic header,
    // which reads as a bug rather than as a quiet day.
    guard case .failed(.invalid) = await compose(provider(text: "{\"blocks\":[]}")) else {
        Issue.record("An empty block array must not compose.")
        return
    }
}

// MARK: - Fenced answers

@Test("a fenced answer is read, because models write fences when told not to")
func fencedAnswerIsAccepted() async {
    let fenced = "```json\n\(goodAnswer)\n```"

    guard case let .composed(report) = await compose(provider(text: fenced)) else {
        Issue.record("A fenced answer must still compose.")
        return
    }
    #expect(report.document.blocks.count == 1)
}

@Test("fence stripping never eats a first line of real content")
func fenceStrippingIsPositional() {
    // The language tag is discarded by POSITION, not by matching a list of tags — but only when a
    // fence opened, so an unfenced answer is returned whole.
    #expect(ReportComposer.stripFence("```\n{\"a\":1}\n```") == "{\"a\":1}")
    #expect(ReportComposer.stripFence("```json\n{\"a\":1}\n```") == "{\"a\":1}")
    #expect(ReportComposer.stripFence("{\"a\":1}") == "{\"a\":1}")
}

// MARK: - Retry

@Test("a bad first answer is corrected once, and the correction quotes what was wrong")
func oneRetryOnABadDocument() async throws {
    let scripted = ScriptedProvider(answers: [
        "{\"blocks\":[{\"blockKind\":\"count\",\"value\":0,\"label\":\"unread\"}]}",
        goodAnswer
    ])

    guard case let .composed(report) = await compose(scripted) else {
        Issue.record("The second answer was well-formed and must compose.")
        return
    }
    #expect(report.attempts == 2)
    #expect(scripted.callCount == 2)

    // The model is corrected on what it actually wrote, not on a paraphrase: its own answer goes
    // back as an assistant turn, followed by the specific complaint.
    let second = try #require(scripted.recordedRequests().last)
    #expect(second.messages.count == 4)
    #expect(second.messages[2].role == .assistant)
    #expect(second.messages[3].content.contains("value"))
}

@Test("a second bad answer ends it rather than looping")
func retriesAreBounded() async {
    let bad = "{\"blocks\":[{\"blockKind\":\"count\",\"value\":0,\"label\":\"unread\"}]}"
    let scripted = ScriptedProvider(answers: [bad, bad, goodAnswer])

    guard case .failed(.invalid) = await compose(scripted) else {
        Issue.record("Two bad answers must fail rather than reaching a third.")
        return
    }
    // A third attempt would have succeeded. It is deliberately never made: a repeated failure is a
    // prompt or model problem, and paying for it turns a 9-second surface into a minute of silence.
    #expect(scripted.callCount == ReportComposer.maximumAttempts)
}

// MARK: - Failures that are not the model's fault

@Test("an unreachable runtime is reported without spending a retry")
func unavailableRuntimeIsNotRetried() async {
    let down = MockModelProvider(error: .unavailable("Cannot reach Ollama at http://localhost:11434."))

    guard case let .failed(.unavailable(message)) = await compose(down) else {
        Issue.record("An unreachable runtime is unavailable.")
        return
    }
    // The adapter's own operator-facing guidance reaches the surface intact — it is the only text
    // that says what to actually do about it.
    #expect(message.contains("Cannot reach Ollama"))
}

@Test("a missing model names itself")
func missingModelIsNamed() async {
    let missing = MockModelProvider(error: .modelNotInstalled("qwen3.6:35b-mlx"))

    guard case let .failed(.unavailable(message)) = await compose(missing) else {
        Issue.record("A missing model is unavailable.")
        return
    }
    #expect(message.contains("qwen3.6:35b-mlx"))
}

@Test("a timeout is a timeout, not a bad document")
func timeoutIsItsOwnFailure() async {
    guard case .failed(.timedOut) = await compose(MockModelProvider(error: .timedOut)) else {
        Issue.record("A timeout must not be reported as an invalid document.")
        return
    }
}

@Test("cancellation is reported as cancellation, never as corruption")
func cancellationIsNotAFailure() async {
    // Cancelling an `AsyncThrowingStream` consumer TERMINATES the stream rather than throwing
    // through it, so a cancelled completion arrives looking exactly like a truncated one. The port
    // checks `Task.isCancelled` before concluding a stream broke; this asserts the composer keeps
    // that distinction rather than telling the reader their brief was corrupt.
    guard case .failed(.cancelled) = await compose(MockModelProvider(error: .cancelled)) else {
        Issue.record("A cancelled composition must report cancellation.")
        return
    }
}

@Test("a runtime fault is never dressed up as a bad brief")
func runtimeFaultsAreUnavailable() async {
    guard case .failed(.unavailable) = await compose(MockModelProvider(error: .contextExceeded)) else {
        Issue.record("A context overflow is a runtime condition, not a wrong document.")
        return
    }
    guard case .failed(.unavailable) = await compose(MockModelProvider(error: .decodeFailed("bad NDJSON"))) else {
        Issue.record("An unreadable runtime reply is not the model composing badly.")
        return
    }
}

// MARK: - Configuration

@Test("a report with no composer entry opts out rather than failing")
func unconfiguredReportOptsOut() async {
    let outcome = await ReportComposer(
        provider: provider(text: goodAnswer), profiles: profiles, composers: composers()
    ).compose(ReportCompositionRequest(reportID: "open-schedule", snapshot: .object([:])))

    guard case let .failed(.unavailable(message)) = outcome else {
        Issue.record("A report with no entry is not composed by a model.")
        return
    }
    #expect(message.contains("isn\u{2019}t composed by a model"))
}

@Test("a composer naming a profile the catalog does not resolve degrades honestly")
func unresolvableProfileDegrades() async {
    // The config layer rejects this combination at validation, so reaching it means a catalog
    // changed underneath a running app. It must still be an honest surface state, not a crash.
    guard case .failed(.unavailable) = await compose(provider(text: goodAnswer), profile: .deep) else {
        Issue.record("An unresolvable profile must degrade rather than throw.")
        return
    }
}

@Test("every failure carries something a reader can actually be shown")
func failuresAreReaderFacing() {
    // A reader cannot act on `/blocks/3/value expected String`, and a report rendering a decoder's
    // complaint is worse than one saying it could not be written.
    let failures: [ReportCompositionFailure] = [
        .unavailable("Ollama is not running."),
        .timedOut,
        .cancelled,
        .truncated(attempts: 2),
        .invalid(reason: "/blocks/3/value expected String", attempts: 2)
    ]

    for failure in failures {
        #expect(!failure.readerFacingMessage.isEmpty)
        #expect(!failure.readerFacingMessage.contains("/blocks"))
    }
}

// MARK: - Action references

@Test("a model-chosen action name is held to the contract's own pattern, ASCII included")
func actionNamesFollowTheSchemaPattern() {
    func violations(_ action: String) -> [ReportBlockBounds.Violation] {
        ReportBlockBounds.violations(in: [
            Block(
                blockKind: .proposal, greetingSize: nil, label: nil, leaderboardPreview: nil,
                leaderboardRows: nil, lineEmphasis: nil, listItems: nil, metricTone: nil,
                reportAction: nil,
                reportActions: [ReportActionElement(action: action, params: nil)],
                scoreboardSides: nil, text: "Proposed.", value: nil
            )
        ])
    }

    #expect(violations("open-mail").isEmpty)
    #expect(violations("check-scoreboard-2").isEmpty)

    // Once a model composes the document, every clickable thing in it is a model-chosen
    // destination. An unresolvable name renders as inert text rather than a control, so this is
    // not a security boundary — it is about failing where the fault is legible.
    #expect(!violations("Open-Mail").isEmpty)
    #expect(!violations("-open").isEmpty)
    #expect(!violations("open_mail").isEmpty)
    // Unicode that Swift's own `isLowercase` / `isNumber` would wave through while the schema's
    // `^[a-z][a-z0-9-]*$` rejects it. A bound laxer than its contract just moves the failure later.
    #expect(!violations("ouvrir-café").isEmpty)
    #expect(!violations("open-mail-٣").isEmpty)
}

// MARK: - A header the model writes and the host throws away

private let greetingAnswer = """
{"blocks":[{"blockKind":"greeting","text":"Good morning. Thursday, 27 August — light rain, 63°F.","greetingSize":"hero"},{"blockKind":"line","text":"Your investor call is at 9:30.","lineEmphasis":"normal"}]}
"""

@Test("a greeting the model writes is discarded when the report writes its own")
func greetingIsDiscarded() async throws {
    // Told plainly NOT to restate the header, the model restated it on 6 of 9 measured
    // compositions: opening with the day and the weather is what a brief looks like, and the
    // instruction was fighting the shape of the task rather than a bad habit. So it is asked for a
    // greeting and the greeting is thrown away — the outcome becomes structural instead of a matter
    // of the model's compliance.
    guard case let .composed(report) = await compose(
        provider(text: greetingAnswer), discardsGreeting: true
    ) else {
        Issue.record("A well-formed answer must compose.")
        return
    }

    #expect(report.document.blocks.count == 1)
    #expect(report.document.blocks.first?.text == "Your investor call is at 9:30.")
    #expect(!report.document.blocks.contains { $0.blockKind == .greeting })
}

@Test("a report that writes no header of its own keeps the model's greeting")
func greetingIsKeptByDefault() async throws {
    // Discarding is a property of the REPORT, not of the tier: a surface with no deterministic
    // opening should keep whatever the model wrote.
    guard case let .composed(report) = await compose(provider(text: greetingAnswer)) else {
        Issue.record("A well-formed answer must compose.")
        return
    }

    #expect(report.document.blocks.count == 2)
    #expect(report.document.blocks.first?.blockKind == .greeting)
}

@Test("a discarded greeting never reaches a streaming surface")
func discardedGreetingIsNotStreamed() async throws {
    // Filtered on the way out as well as at the end, or the greeting would appear as the first
    // block to arrive and then vanish when the document settled — a visible flash of something the
    // reader was never meant to see.
    let seen = BlockRecorder()
    _ = await compose(
        provider(text: greetingAnswer),
        discardsGreeting: true,
        onBlocks: { blocks in Task { await seen.record(blocks) } }
    )

    try await Task.sleep(nanoseconds: 50_000_000)
    let emissions = await seen.emissions
    #expect(!emissions.isEmpty)
    for emission in emissions {
        #expect(!emission.contains { $0.blockKind == .greeting })
    }
}

@Test("a document of nothing but a greeting is a failed composition, not an empty brief")
func greetingOnlyDocumentFails() async {
    // Everything the model wrote was a header this report supplies itself, so there is no report
    // left. A retry is the right answer; a blank body under a correct header is not.
    let onlyGreeting = """
    {"blocks":[{"blockKind":"greeting","text":"Good morning.","greetingSize":"hero"}]}
    """

    guard case let .failed(.invalid(reason, _)) = await compose(
        provider(text: onlyGreeting), discardsGreeting: true
    ) else {
        Issue.record("A greeting-only document must not compose.")
        return
    }
    #expect(reason.contains("nothing but a greeting"))
}

@Test("the block cap counts what the model wrote, not what survived the filter")
func capCountsRawOutput() async {
    // Checking the kept blocks instead would let a runaway of sixty greetings through on the
    // grounds that none of them survived — the cap exists to catch a model that will not stop.
    let many = (0..<20).map { _ in "{\"blockKind\":\"greeting\",\"text\":\"Good morning.\"}" }
        .joined(separator: ",")

    guard case let .failed(.invalid(reason, _)) = await compose(
        provider(text: "{\"blocks\":[\(many)]}"), discardsGreeting: true
    ) else {
        Issue.record("Twenty blocks against a cap of twelve must not compose.")
        return
    }
    #expect(reason.contains("20 blocks"))
}

private actor BlockRecorder {
    private(set) var emissions: [[Block]] = []
    func record(_ blocks: [Block]) { emissions.append(blocks) }
}
