import Foundation
import CerebralContracts

/// Composes a Report document by asking a model to write its blocks (NIC-250).
///
/// This is v2 of the Composer at the seam the quick-actions plan cut:
/// `providers → Assembler → Snapshot → Composer → ReportDocument → Renderer`. Same input type,
/// same output type, renderer unchanged. It reads no providers and calls no tools — the passive
/// tier composes prose and proposals and executes nothing — so the whole of its power is turning
/// typed data into paragraphs.
///
/// **The model writes `blocks`; this type writes the envelope.** `schemaVersion` and `reportId`
/// are values the system already knows, and every failure in the first spike was a malformed
/// envelope field rather than a malformed report. Narrowing the model's output to the part that
/// needs judgement deleted that error class rather than mitigating it.
///
/// **Validation is decoding, plus bounds.** Output is requested as plain text rather than through
/// `ModelResponseFormat.jsonSchema`, because the runtime serving this today does not enforce a
/// schema it is given: told explicitly to emit a string, Ollama produced `value: 0` on 6 of 6 runs
/// of one snapshot *with the schema supplied*, statistically indistinguishable from supplying
/// nothing. So the guarantee is taken where it can actually be had — decoding into the generated
/// `Block` rejects a wrong leaf type or an unknown enum case, and ``ReportBlockBounds`` catches the
/// lengths `Codable` has no opinion about. A runtime that genuinely enforces a schema
/// (`ModelRuntimeCapabilities.enforcesResponseSchema`) can be given one later; that path needs a
/// schema literal in Swift, which nothing ships yet.
public struct ReportComposer: Sendable {
    /// Ollama's structured-output mode measured no better than prompting, so the composer asks for
    /// text and validates. See the type's note.
    private static let responseFormat: ModelResponseFormat = .text

    /// What the schema documents as the absent-value default. Stated once, here, so a composer
    /// entry that omits it and one that writes `0.4` behave identically.
    static let defaultTemperature = 0.4

    /// One retry, never more. A second failure is a prompt or model problem, not luck: at ~250
    /// output tokens a retry is cheap, but a loop that keeps paying for the same misunderstanding
    /// turns a 9-second surface into a minute of silence.
    static let maximumAttempts = 2

    private let provider: any ModelProvider
    private let profiles: ModelProfileCatalog
    private let composers: CerebralHelmModelComposerCatalog

    public init(
        provider: any ModelProvider,
        profiles: ModelProfileCatalog,
        composers: CerebralHelmModelComposerCatalog
    ) {
        self.provider = provider
        self.profiles = profiles
        self.composers = composers
    }

    /// Composes `request`, retrying once on a document that arrives wrong.
    ///
    /// Never throws. Every way this can fail is a state a surface has to render honestly, and an
    /// error escaping here would make "Ollama is not running" indistinguishable from a bug.
    /// - Parameter onBlocks: called as blocks arrive, with **every block so far** rather than the
    ///   new ones. Whole-set semantics, matching the health-check run the bridge already streams:
    ///   a consumer that had to reconcile per-block updates could drift out of step, and a retry
    ///   simply replaces the set rather than needing an undo. Omit it for a buffered composition.
    public func compose(
        _ request: ReportCompositionRequest,
        onBlocks: (@Sendable ([Block]) -> Void)? = nil
    ) async -> ReportCompositionOutcome {
        guard let composer = composers.composerReports.first(
            where: { $0.composerReportID == request.reportID }
        ) else {
            // Not an error: a report with no entry is composed deterministically, which is how a
            // surface opts out of model composition.
            return .failed(.unavailable("This report isn\u{2019}t composed by a model."))
        }
        guard
            let profileID = ModelCapabilityProfile(rawValue: composer.modelProfileID.rawValue),
            let resolution = profiles.resolve(profileID)
        else {
            return .failed(.unavailable("No model is configured for this report."))
        }

        let options = resolution.options(
            temperature: composer.composerTemperature ?? Self.defaultTemperature,
            // Required by configuration, so it can never be absent here. A grammar-constrained
            // caller MUST set this, and an unconstrained one still should: the measured runaway
            // ran to 15,655 tokens before the context wall truncated it mid-token.
            maxOutputTokens: composer.composerMaxOutputTokens,
            responseFormat: Self.responseFormat
        )

        /// Drops the blocks the host writes itself.
        ///
        /// The daily brief renders its greeting, date and weather deterministically above the
        /// model's first block, and the model is ASKED for a greeting anyway so that it can be
        /// thrown away. Told plainly not to restate the header it restated it on 6 of 9 measured
        /// compositions — opening with the day and the weather is simply what a brief looks like,
        /// and the instruction was fighting the shape of the task rather than a bad habit.
        ///
        /// Filtering by block KIND rather than by position, so it holds wherever the model puts it
        /// and does not need the first block to be the one it guessed.
        ///
        /// The same pass drops any `reportActions` entry naming an action that is not in the
        /// catalog. `report-document.schema.json` constrains the id's SHAPE and not its membership,
        /// so nothing upstream of here checks that the app has it.
        ///
        /// The renderer is not fooled — `resolveQuickAction` returns nil for an unregistered id and
        /// `ActionLink` falls back to inert text, so a phantom control is never pressable. What the
        /// reader still gets is an offer, labelled from the id, that the app cannot take up. Drop
        /// it and the prose stands on its own, which is the honest version of the same sentence. A
        /// prompt rule alone would leave this one sampling accident away.
        let offerable = Set(composers.composerActions.map(\.composerActionID))
        let keep: @Sendable ([Block]) -> [Block] = { blocks in
            let grounded = blocks.map { block -> Block in
                guard let actions = block.reportActions, !actions.isEmpty else { return block }
                let allowed = actions.filter { offerable.contains($0.action) }
                if allowed.count == actions.count { return block }
                // Rebuilt rather than mutated: the generated contract types are immutable, which
                // is the right default for something decoded off a model's output.
                return Block(
                    blockKind: block.blockKind,
                    greetingSize: block.greetingSize,
                    label: block.label,
                    leaderboardPreview: block.leaderboardPreview,
                    leaderboardRows: block.leaderboardRows,
                    lineEmphasis: block.lineEmphasis,
                    listItems: block.listItems,
                    metricTone: block.metricTone,
                    reportAction: block.reportAction,
                    reportActions: allowed.isEmpty ? nil : allowed,
                    scoreboardSides: block.scoreboardSides,
                    text: block.text,
                    value: block.value
                )
            }
            return composer.composerDiscardsGreeting == true
                ? grounded.filter { $0.blockKind != .greeting }
                : grounded
        }

        // Filtered on the way out too, so a discarded greeting never reaches a surface and flashes
        // there before the rest of the document catches up.
        let progress: (@Sendable ([Block]) -> Void)?
        if let onBlocks {
            progress = { blocks in onBlocks(keep(blocks)) }
        } else {
            progress = nil
        }

        var messages: [ModelMessage] = [
            .system(composers.composerSystemPrompt),
            .user(Self.userContent(request: request, instruction: composer.composerInstruction))
        ]

        var attempt = 0
        var lastFailure: ReportCompositionFailure = .invalid(reason: "No attempt was made.", attempts: 0)

        while attempt < Self.maximumAttempts {
            attempt += 1

            let completion: ModelCompletion
            do {
                completion = try await stream(
                    ModelRequest(messages: messages, options: options),
                    onBlocks: progress
                )
            } catch let error as ModelProviderError {
                // A transport or lifecycle failure is not something a retry fixes, and cancellation
                // is not a failure at all. Only a bad *document* earns a second attempt.
                return .failed(Self.failure(from: error))
            } catch {
                return .failed(.unavailable("The model could not be reached."))
            }

            switch Self.blocks(from: completion.text, cap: composer.composerMaxOutputTokens, usage: completion.usage) {
            case let .success(blocks):
                // Bounds and the block cap are checked against what the model ACTUALLY produced.
                // Checking the kept blocks instead would let a runaway of sixty greetings through
                // on the grounds that none of them survived.
                let overruns = ReportBlockBounds.violations(in: blocks)
                let kept = keep(blocks)
                if overruns.isEmpty, blocks.count <= composer.composerMaxBlocks, !kept.isEmpty {
                    return .composed(ComposedReport(
                        document: CerebralHelmReportDocument(
                            blocks: kept,
                            // Composed from a snapshot the host assembled, not from a fetch the
                            // reader can repeat. Offering a refresh here would promise something
                            // the document cannot do.
                            refreshable: nil,
                            reportID: request.reportID,
                            schemaVersion: Self.documentSchemaVersion
                        ),
                        usage: completion.usage,
                        attempts: attempt
                    ))
                }

                let reason: String
                if !overruns.isEmpty {
                    reason = overruns.map { $0.description }.joined(separator: "; ")
                } else if blocks.count > composer.composerMaxBlocks {
                    reason = "/blocks has \(blocks.count) blocks, more than the \(composer.composerMaxBlocks) this report allows"
                } else {
                    // Everything the model wrote was a greeting, which this report supplies itself —
                    // so there is no report left. A retry is the right answer, not a blank body.
                    reason = "the document contained nothing but a greeting, which this report writes itself"
                }
                lastFailure = .invalid(reason: reason, attempts: attempt)
                messages += Self.correction(completion.text, reason: reason)

            case let .failure(problem):
                switch problem {
                case .truncated:
                    lastFailure = .truncated(attempts: attempt)
                    // Retrying a truncation with the same budget is only worth it because the
                    // model is asked to be shorter, not because the cap changed.
                    messages += Self.correction(
                        completion.text,
                        reason: "the document was cut off before it finished. Write fewer, shorter blocks."
                    )
                case let .malformed(detail):
                    lastFailure = .invalid(reason: detail, attempts: attempt)
                    messages += Self.correction(completion.text, reason: detail)
                }
            }
        }

        return .failed(lastFailure)
    }

    // MARK: - Reading the stream

    /// Collects a completion, handing finished blocks to `onBlocks` as they close.
    ///
    /// This replaces `ModelProvider.complete(_:)` rather than wrapping it, because that extension
    /// collects the stream itself and there is no seam in it to watch the deltas go past. The two
    /// behaviours it is careful to keep are the ones that method documents, and both are load-bearing:
    /// a stream that ends without its terminal event is a BROKEN stream rather than an empty answer,
    /// and cancellation is checked BEFORE concluding anything, because cancelling an
    /// `AsyncThrowingStream` consumer terminates the stream rather than throwing through it — so a
    /// cancelled request arrives here looking exactly like a truncated one.
    private func stream(
        _ request: ModelRequest,
        onBlocks: (@Sendable ([Block]) -> Void)?
    ) async throws -> ModelCompletion {
        var text = ""
        var usage: ModelUsage?
        var parser = IncrementalBlockParser()
        var seen: [Block] = []

        do {
            for try await event in provider.stream(request) {
                switch event {
                case let .textDelta(delta):
                    text += delta
                    guard let onBlocks else { continue }
                    let arrived = parser.consume(delta)
                    guard !arrived.isEmpty else { continue }
                    seen += arrived
                    onBlocks(seen)
                case let .completed(reported):
                    usage = reported
                // Deliberation is off for composition, and the passive tier calls nothing — but a
                // runtime that emitted either must not break the read.
                case .thinkingDelta, .toolCall:
                    continue
                }
            }
        } catch is CancellationError {
            throw ModelProviderError.cancelled
        }

        if Task.isCancelled { throw ModelProviderError.cancelled }
        guard let usage else {
            throw ModelProviderError.decodeFailed("The stream ended without reporting completion.")
        }
        return ModelCompletion(text: text, toolCalls: [], usage: usage)
    }

    // MARK: - The prompt

    /// The report id, its instruction, and the snapshot — in that order, and deterministically.
    ///
    /// `JSONValue.serialized()` sorts keys, which matters for more than tidiness: each distinct
    /// prompt prefix is a distinct prefix-cache prefix, and a snapshot whose keys reordered between
    /// runs would miss a cache measured at 98.7% hit rate in steady state.
    static func userContent(request: ReportCompositionRequest, instruction: String) -> String {
        let snapshot = (try? request.snapshot.serialized())
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        reportId: \(request.reportID)

        \(instruction)

        SNAPSHOT:
        \(snapshot)
        """
    }

    /// The model's own answer, then what was wrong with it.
    ///
    /// Feeding the failed attempt back as an `assistant` turn rather than describing it keeps the
    /// transcript honest — the model is corrected on what it actually wrote, not on a paraphrase —
    /// and it costs nothing, because the composition is short by construction.
    static func correction(_ answer: String, reason: String) -> [ModelMessage] {
        [
            .assistant(answer),
            .user("""
            That document could not be used: \(reason).

            Reply again with a JSON object containing ONLY a "blocks" array. Every "value" and \
            every "label" is a string, even when it holds a number.
            """)
        ]
    }

    // MARK: - Reading the answer

    static let documentSchemaVersion = "1.0.0"

    /// Why a completion yielded no blocks. Truncation and malformation are kept apart all the way
    /// down, because they are the two things finding 16 says a schema check alone cannot separate.
    enum ReadProblem: Error, Equatable {
        case truncated
        case malformed(String)
    }

    private struct Envelope: Decodable {
        let blocks: [Block]
    }

    /// Parses `text` into blocks, or says which way it failed.
    static func blocks(from text: String, cap: Int, usage: ModelUsage) -> Swift.Result<[Block], ReadProblem> {
        let cleaned = stripFence(text)

        guard let data = cleaned.data(using: .utf8) else {
            return .failure(.malformed("the answer was not readable text"))
        }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard !envelope.blocks.isEmpty else {
                // An empty array is schema-legal and still a failed composition. The snapshot being
                // empty is something the model is told to SAY, not something it answers with
                // silence — and the deterministic header above it means a blank body reads as a
                // bug rather than as a quiet day.
                return .failure(.malformed("the document contained no blocks"))
            }
            return .success(envelope.blocks)
        } catch {
            if looksTruncated(cleaned, cap: cap, usage: usage) {
                return .failure(.truncated)
            }
            return .failure(.malformed(Self.describe(error)))
        }
    }

    /// Whether a document that would not parse was *cut off* rather than wrong.
    ///
    /// Two signals, either sufficient. Spending the whole output budget is the direct evidence; a
    /// body that does not close its own object is the circumstantial kind, and it catches a runtime
    /// that stopped for its own reasons without reporting a token count.
    static func looksTruncated(_ text: String, cap: Int, usage: ModelUsage) -> Bool {
        if let output = usage.outputTokens, output >= cap { return true }
        return !text.hasSuffix("}")
    }

    /// A decoding error as something a model can act on.
    ///
    /// `DecodingError` carries the coding path and the expected type, which is exactly the
    /// correction to quote back — "/blocks/3/value expected String" is actionable where
    /// "The data couldn't be read" is not.
    static func describe(_ error: any Error) -> String {
        guard let decoding = error as? DecodingError else {
            return "the answer was not valid JSON"
        }
        func path(_ context: DecodingError.Context) -> String {
            let pointer = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
            return pointer.isEmpty ? "/" : "/" + pointer.joined(separator: "/")
        }
        switch decoding {
        case let .typeMismatch(type, context):
            return "\(path(context)) expected \(type)"
        case let .valueNotFound(type, context):
            return "\(path(context)) is missing a \(type)"
        case let .keyNotFound(key, context):
            return "\(path(context)) is missing \"\(key.stringValue)\""
        case let .dataCorrupted(context):
            // An unknown enum case lands here — an invented block kind, tone or emphasis.
            return context.codingPath.isEmpty
                ? "the answer was not valid JSON"
                : "\(path(context)) is not one of the allowed values"
        @unknown default:
            return "the answer did not fit the report contract"
        }
    }

    /// Removes a Markdown code fence, which a model asked for "JSON and nothing else" still
    /// sometimes writes anyway. Verified behaviour, not a defensive guess: the eval harness needed
    /// exactly this.
    static func stripFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        trimmed.removeFirst(3)
        if let newline = trimmed.firstIndex(of: "\n") {
            // Drop the language tag ("json") when there is one, but never a whole first line of
            // content: only the text before the newline is discarded, and it is a tag by position.
            trimmed = String(trimmed[trimmed.index(after: newline)...])
        }
        if let close = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<close.lowerBound])
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Failure mapping

    /// The port's error taxonomy onto the composer's.
    ///
    /// `contextExceeded` and `decodeFailed` become `unavailable` rather than `invalid`: neither is
    /// something the model did with its answer, and reporting a runtime fault as a bad document
    /// would send the reader looking at their brief for a problem that is in the daemon.
    static func failure(from error: ModelProviderError) -> ReportCompositionFailure {
        switch error {
        case let .unavailable(message):
            return .unavailable(message)
        case let .modelNotInstalled(model):
            return .unavailable("The configured model (\(model)) is not installed.")
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .contextExceeded:
            return .unavailable("The brief did not fit the model\u{2019}s context window.")
        case let .decodeFailed(detail):
            return .unavailable("The model runtime replied with something unreadable: \(detail)")
        case let .providerFailed(detail):
            return .unavailable("The model runtime failed: \(detail)")
        }
    }
}
