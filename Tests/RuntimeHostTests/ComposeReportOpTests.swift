import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// NIC-228 / NIC-253: the `composeReport` op, where a model's prose first crosses the bridge.
///
/// Three things are worth protecting. The request carries **only a report id** — the snapshot is
/// assembled host-side, so a message preview or a profile note has no path into the web layer even
/// in principle. Blocks are **streamed**, because nine seconds of silence and nine seconds of
/// visible arrival feel nothing alike. And **no failure is an error response**: every way a
/// composition can fail is a state the report region renders, and a `status: "error"` would send the
/// dashboard down its generic failure path instead of showing the reader what happened.

private func composeOpRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct CompositionPayload: Decodable {
    struct BlockDTO: Decodable { let blockKind: String; let text: String? }
    let reportId: String
    let state: String
    let blocks: [BlockDTO]
    let complete: Bool
    let reason: String?
    let firstBlockMs: Int?
    let totalMs: Int?
}

/// Collects the emitted event JSON. Emissions come from a detached task, so a test waits for them
/// rather than assuming they have landed.
private final class Emissions: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [String] = []

    func emit(_ json: String) { lock.lock(); defer { lock.unlock() }; raw.append(json) }

    func compositions() -> [CompositionPayload] {
        lock.lock()
        let snapshot = raw
        lock.unlock()
        return snapshot.compactMap { json in
            guard let data = json.data(using: .utf8),
                  let event = try? JSONDecoder().decode(EventEnvelope.self, from: data),
                  event.type == "report.composition.changed"
            else { return nil }
            return event.payload
        }
    }

    func waitForComplete(within seconds: Double = 3) async -> [CompositionPayload] {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let seen = compositions()
            if seen.contains(where: { $0.complete }) { return seen }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return compositions()
    }

    private struct EventEnvelope: Decodable {
        let type: String
        let payload: CompositionPayload
    }
}

private func makeComposeSession(
    composeReport: (@Sendable (String, @escaping @Sendable ([Block]) -> Void) async -> ReportCompositionOutcome)? = nil
) throws -> (session: BridgeSession, emissions: Emissions) {
    let paths = try WorkspacePaths.temporary(repositoryRoot: composeOpRepositoryRoot())
    let emissions = Emissions()
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        composeReport: composeReport,
        emitEventJSON: { emissions.emit($0) }
    )
    return (session, emissions)
}

private func composeRequest(_ json: String = #"{"reportId":"daily-brief"}"#) -> CerebralHelmBridgeOperationRequest {
    let payload = (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
    return CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_composereport01", operation: .composeReport, payload: payload,
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

private struct StartResult: Decodable {
    let state: String
    let reason: String?
}

private func decodeStart(_ response: CerebralHelmBridgeOperationResponse) throws -> StartResult {
    try JSONDecoder().decode(StartResult.self, from: try JSONEncoder().encode(response.payload))
}

private func block(_ text: String) -> Block {
    Block(
        blockKind: .line, greetingSize: nil, label: nil, leaderboardPreview: nil,
        leaderboardRows: nil, lineEmphasis: .normal, listItems: nil, metricTone: nil,
        reportAction: nil, reportActions: nil, scoreboardSides: nil, text: text, value: nil
    )
}

private func composed(_ blocks: [Block]) -> ComposedReport {
    ComposedReport(
        document: CerebralHelmReportDocument(
            blocks: blocks, refreshable: nil, reportID: "daily-brief", schemaVersion: "1.0.0"
        ),
        usage: ModelUsage(outputTokens: 40, wallDuration: .seconds(9)),
        attempts: 1
    )
}

private actor ReportIDRecorder {
    private(set) var value: String?
    func record(_ id: String) { value = id }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

// MARK: - Streaming

@Test("the operation answers that work began, and the blocks follow as events")
func blocksArriveAsEvents() async throws {
    // The response is not the document. Awaiting one would put nine seconds of silence in front of
    // the reader, which is the thing this exists to remove.
    let (session, emissions) = try makeComposeSession { _, onBlocks in
        onBlocks([block("One.")])
        onBlocks([block("One."), block("Two.")])
        return .composed(composed([block("One."), block("Two.")]))
    }

    let response = await session.execute(composeRequest())
    #expect(try decodeStart(response).state == "composing")

    let seen = await emissions.waitForComplete()
    #expect(seen.count == 3)
    #expect(seen.map(\.blocks.count) == [1, 2, 2])
    // Whole-set semantics: each emission REPLACES rather than appends, so a consumer never has to
    // reconcile and a retry that discarded its first attempt simply sends a shorter set.
    #expect(seen[1].blocks.map(\.text) == ["One.", "Two."])
    #expect(seen.map(\.complete) == [false, false, true])
    #expect(seen.last?.state == "ready")
    #expect(seen.allSatisfy { $0.reportId == "daily-brief" })
}

@Test("time to the first block is reported apart from the total")
func firstBlockIsTimedSeparately() async throws {
    // They answer different questions — how long until the reader sees something, and how long until
    // it is finished — and the first is what decides whether a long composition reads as arrival.
    let (session, emissions) = try makeComposeSession { _, onBlocks in
        try? await Task.sleep(nanoseconds: 20_000_000)
        onBlocks([block("One.")])
        return .composed(composed([block("One.")]))
    }

    _ = await session.execute(composeRequest())
    let terminal = try #require(await emissions.waitForComplete().last)

    #expect(terminal.firstBlockMs != nil)
    #expect((terminal.totalMs ?? 0) >= (terminal.firstBlockMs ?? 0))
}

@Test("a second request while one is in flight joins it rather than starting a competitor")
func compositionsDoNotOverlap() async throws {
    // Two runs would interleave their emissions and the reader would watch the brief rewrite itself
    // between two truths.
    let started = Counter()
    let (session, emissions) = try makeComposeSession { _, onBlocks in
        await started.increment()
        try? await Task.sleep(nanoseconds: 60_000_000)
        onBlocks([block("One.")])
        return .composed(composed([block("One.")]))
    }

    _ = await session.execute(composeRequest())
    let second = await session.execute(composeRequest())

    // The second is answered with the run already going, not refused.
    #expect(try decodeStart(second).state == "composing")
    _ = await emissions.waitForComplete()
    #expect(await started.value == 1)
}

// MARK: - Failures are states, not errors

@Test("a failed composition emits its reason and NO blocks")
func failuresDiscardWhatStreamed() async throws {
    // Whatever streamed before a failure came from an attempt that did not survive validation, so
    // showing it as final would render a document the composer rejected.
    let (session, emissions) = try makeComposeSession { _, onBlocks in
        onBlocks([block("A half-written thought.")])
        return .failed(.invalid(reason: "/blocks/3/value expected String", attempts: 2))
    }

    _ = await session.execute(composeRequest())
    let terminal = try #require(await emissions.waitForComplete().last)

    #expect(terminal.complete)
    #expect(terminal.state == "unavailable")
    #expect(terminal.blocks.isEmpty)
    // A reader cannot act on `/blocks/3/value expected String`.
    #expect(terminal.reason?.contains("/blocks") == false)
    #expect(terminal.reason?.contains("couldn\u{2019}t be written") == true)
}

@Test("each failure keeps its own reader-facing sentence")
func failuresAreReaderFacing() async throws {
    let cases: [(ReportCompositionFailure, String)] = [
        (.unavailable("Cannot reach Ollama at http://localhost:11434."), "Ollama"),
        (.timedOut, "too long"),
        (.truncated(attempts: 2), "cut off")
    ]

    for (failure, expected) in cases {
        let (session, emissions) = try makeComposeSession { _, _ in .failed(failure) }
        let response = await session.execute(composeRequest())

        // Not an error response. The region has a state for this; the generic failure path does not.
        #expect(response.status == .ok)
        let terminal = try #require(await emissions.waitForComplete().last)
        #expect(terminal.reason?.contains(expected) == true, "expected \u{201C}\(expected)\u{201D}")
    }
}

@Test("a host with no model configured answers honestly and emits nothing")
func noComposerIsUnavailable() async throws {
    let (session, emissions) = try makeComposeSession(composeReport: nil)

    let response = await session.execute(composeRequest())
    #expect(response.status == .ok)
    let result = try decodeStart(response)
    #expect(result.state == "unavailable")
    #expect(result.reason?.contains("No model is configured") == true)
    // Nothing was started, so nothing streams — the refusal itself is the whole answer.
    #expect(emissions.compositions().isEmpty)
}

@Test("a request with no report id is rejected as invalid input")
func missingReportIDIsInvalid() async throws {
    // The one genuine error here: a malformed request is a caller bug, not a surface state.
    let (session, _) = try makeComposeSession { _, _ in .composed(composed([block("One.")])) }

    #expect(await session.execute(composeRequest("{}")).status == .error)
    #expect(await session.execute(composeRequest(#"{"reportId":"  "}"#)).status == .error)
}

@Test("the request carries a report id and nothing else")
func requestCarriesOnlyAReportID() async throws {
    // The structural half of the host-side decision: there is no field here a preview or a profile
    // note could travel in, so the web layer cannot receive one by accident or by a later
    // well-meaning addition.
    let seen = ReportIDRecorder()
    let (session, emissions) = try makeComposeSession { reportID, _ in
        await seen.record(reportID)
        return .composed(composed([block("One.")]))
    }

    _ = await session.execute(composeRequest())
    _ = await emissions.waitForComplete()
    #expect(await seen.value == "daily-brief")
}
