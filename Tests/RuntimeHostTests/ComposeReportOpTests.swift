import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// NIC-228: the `composeReport` op, which is where a model's prose first crosses the bridge.
///
/// Two things are worth protecting here. **No failure is an error response** — every way a
/// composition can fail is a state the report region renders, and a `status: "error"` would send the
/// dashboard down its generic failure path instead of showing the reader what happened. And the
/// request carries **only a report id**: the snapshot is assembled host-side, so a message preview
/// or a profile note has no path into the web layer even in principle.

private func composeOpRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeComposeSession(
    composeReport: (@Sendable (String) async -> ReportCompositionOutcome)? = nil
) throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: composeOpRepositoryRoot())
    return BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        composeReport: composeReport
    )
}

private func composeRequest(_ json: String = #"{"reportId":"daily-brief"}"#) -> CerebralHelmBridgeOperationRequest {
    let payload = (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
    return CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_composereport01", operation: .composeReport, payload: payload,
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

private struct ComposeResultDTO: Decodable {
    struct Document: Decodable {
        struct Block: Decodable { let blockKind: String; let text: String? }
        let schemaVersion: String
        let reportId: String
        let blocks: [Block]
    }
    let state: String
    let reason: String?
    let attempts: Int?
    let totalMs: Int?
    let document: Document?
}

private func decode(_ response: CerebralHelmBridgeOperationResponse) throws -> ComposeResultDTO {
    let data = try JSONEncoder().encode(response.payload)
    return try JSONDecoder().decode(ComposeResultDTO.self, from: data)
}

private func composedDocument() -> ComposedReport {
    ComposedReport(
        document: CerebralHelmReportDocument(
            blocks: [Block(
                blockKind: .line, greetingSize: nil, label: nil, leaderboardPreview: nil,
                leaderboardRows: nil, lineEmphasis: .normal, listItems: nil, metricTone: nil,
                reportAction: nil, reportActions: nil, scoreboardSides: nil,
                text: "Your calendar is clear.", value: nil
            )],
            refreshable: nil,
            reportID: "daily-brief",
            schemaVersion: "1.0.0"
        ),
        usage: ModelUsage(outputTokens: 40, wallDuration: .seconds(9)),
        attempts: 1
    )
}

// MARK: - The composed document

@Test("a composed report crosses with its envelope and its attempt count")
func composedReportCrosses() async throws {
    let session = try makeComposeSession { _ in .composed(composedDocument()) }

    let result = try decode(await session.execute(composeRequest()))
    #expect(result.state == "ready")
    #expect(result.document?.reportId == "daily-brief")
    #expect(result.document?.schemaVersion == "1.0.0")
    #expect(result.document?.blocks.first?.text == "Your calendar is clear.")
    // Surfaced rather than swallowed: a composer that silently needs two attempts every time is a
    // prompt problem wearing a success.
    #expect(result.attempts == 1)
    #expect((result.totalMs ?? -1) >= 0)
}

@Test("the request carries a report id and nothing else")
func requestCarriesOnlyAReportID() async throws {
    // The snapshot is assembled host-side. This is the structural half of that decision: there is
    // no field here a preview or a profile note could travel in, so the web layer cannot receive one
    // by accident or by a later well-meaning addition.
    let seen = ReportIDRecorder()
    let session = try makeComposeSession { reportID in
        await seen.record(reportID)
        return .composed(composedDocument())
    }

    _ = await session.execute(composeRequest(#"{"reportId":"daily-brief"}"#))
    #expect(await seen.value == "daily-brief")
}

// MARK: - Failures are states, not errors

@Test("a host with no model configured answers honestly rather than erroring")
func noComposerIsUnavailable() async throws {
    let session = try makeComposeSession(composeReport: nil)

    let response = await session.execute(composeRequest())
    #expect(response.status == .ok)
    let result = try decode(response)
    #expect(result.state == "unavailable")
    #expect(result.document == nil)
    #expect(result.reason?.contains("No model is configured") == true)
}

@Test("every composition failure arrives as a reader-facing sentence, never a decoder's complaint")
func failuresAreReaderFacing() async throws {
    let cases: [(ReportCompositionFailure, String)] = [
        (.unavailable("Cannot reach Ollama at http://localhost:11434."), "Ollama"),
        (.timedOut, "too long"),
        (.truncated(attempts: 2), "cut off"),
        (.invalid(reason: "/blocks/3/value expected String", attempts: 2), "couldn\u{2019}t be written")
    ]

    for (failure, expected) in cases {
        let session = try makeComposeSession { _ in .failed(failure) }
        let response = await session.execute(composeRequest())

        // Not an error response. The region has a state for this; the generic failure path does not.
        #expect(response.status == .ok)
        let result = try decode(response)
        #expect(result.state == "unavailable")
        #expect(result.reason?.contains(expected) == true, "expected \u{201C}\(expected)\u{201D} in \(result.reason ?? "nil")")
        // A reader cannot act on `/blocks/3/value expected String`.
        #expect(result.reason?.contains("/blocks") == false)
    }
}

@Test("a request with no report id is rejected as invalid input")
func missingReportIDIsInvalid() async throws {
    // The one genuine error here: a malformed request is a caller bug, not a surface state.
    let session = try makeComposeSession { _ in .composed(composedDocument()) }

    #expect(await session.execute(composeRequest("{}")).status == .error)
    #expect(await session.execute(composeRequest(#"{"reportId":"  "}"#)).status == .error)
}

/// Records the report id the composer was asked for.
private actor ReportIDRecorder {
    private(set) var value: String?
    func record(_ id: String) { value = id }
}
