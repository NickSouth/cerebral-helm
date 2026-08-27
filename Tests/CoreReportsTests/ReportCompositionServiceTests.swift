import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-228: assembling and composing as one step, per report.
///
/// The two halves are separate types on purpose, and this is what holds them together. What is
/// worth protecting is that the join stays report-agnostic — the email report and the playlist build
/// should each be an assembler plus an instruction, never a second service — and that a report with
/// no assembler opts out the same honest way a report with no composer entry does.

private let composers = CerebralHelmModelComposerCatalog(
    composerReports: [
        ComposerReport(
            composerInstruction: "Compile the morning brief.",
            composerMaxBlocks: 12,
            composerMaxOutputTokens: 1200,
            composerReportID: "daily-brief",
            composerTemperature: 0.4,
            extensions: nil,
            modelProfileID: .local
        )
    ],
    composerSystemPrompt: "You compose CerebralHelm report documents.",
    extensions: nil,
    schemaVersion: "1.0.0"
)

private let profiles = ModelProfileCatalog(
    resolutions: [
        ModelProfileResolution(
            profile: .local, modelID: "qwen3.6:35b-mlx", runtime: .ollama,
            contextTokens: 16_384, residency: .bounded(.seconds(300)),
            thinking: false, timeout: .seconds(120)
        )
    ]
)

private let answer = """
{"blocks":[{"blockKind":"line","text":"Your calendar is clear.","lineEmphasis":"normal"}]}
"""

private func service(
    assemblers: [String: @Sendable (Date) async -> JSONValue],
    text: String = answer
) -> ReportCompositionService {
    ReportCompositionService(
        assemblers: assemblers,
        composer: ReportComposer(
            provider: MockModelProvider(events: [
                .textDelta(text),
                .completed(ModelUsage(outputTokens: 40, wallDuration: .seconds(9)))
            ]),
            profiles: profiles,
            composers: composers
        )
    )
}

private let now = Date(timeIntervalSince1970: 1_756_200_000)

@Test("the assembler's snapshot is what the composer is given")
func snapshotFlowsFromAssemblerToComposer() async throws {
    let subject = service(assemblers: [
        "daily-brief": { _ in .object(["calendar": .object(["state": .string("ready")])]) }
    ])

    guard case let .composed(report) = await subject.compose(reportID: "daily-brief", now: now) else {
        Issue.record("A well-formed answer must compose.")
        return
    }
    #expect(report.document.reportID == "daily-brief")
    #expect(report.document.blocks.first?.text == "Your calendar is clear.")
}

@Test("the assembler is given the instant the caller asked about, not its own clock")
func assemblerReceivesTheCallersClock() async {
    // A brief is reproducible: the same instant and the same providers produce the same snapshot,
    // which is what lets a test assert on it and keeps the prompt's cache prefix stable.
    let seen = Recorder()
    let subject = service(assemblers: [
        "daily-brief": { at in
            await seen.record(at)
            return .object([:])
        }
    ])

    _ = await subject.compose(reportID: "daily-brief", now: now)
    #expect(await seen.value == now)
}

@Test("a report with no assembler opts out rather than failing")
func unknownReportOptsOut() async {
    let subject = service(assemblers: ["daily-brief": { _ in .object([:]) }])

    guard case let .failed(.unavailable(message)) = await subject.compose(
        reportID: "open-schedule", now: now
    ) else {
        Issue.record("A report with no assembler is not model-composed.")
        return
    }
    // The same sentence a report with no composer entry gets: two ways to opt out, one honest
    // answer, so a surface never has to tell them apart.
    #expect(message.contains("isn\u{2019}t composed by a model"))
}

@Test("the service says which reports it can compose without spending an assembly to find out")
func composableReportsAreDeclared() {
    let subject = service(assemblers: [
        "daily-brief": { _ in .object([:]) },
        "email-report": { _ in .object([:]) }
    ])

    #expect(subject.composableReportIDs == ["daily-brief", "email-report"])
}

@Test("a composition failure reaches the caller intact rather than as a thrown error")
func failuresAreReturned() async {
    // Never throws, for the same reason the composer does not: every failure is a state a surface
    // has to render, and an error escaping would make "Ollama is not running" look like a bug.
    let subject = ReportCompositionService(
        assemblers: ["daily-brief": { _ in .object([:]) }],
        composer: ReportComposer(
            provider: MockModelProvider(error: .unavailable("Cannot reach Ollama.")),
            profiles: profiles,
            composers: composers
        )
    )

    guard case let .failed(.unavailable(message)) = await subject.compose(
        reportID: "daily-brief", now: now
    ) else {
        Issue.record("An unreachable runtime must reach the caller as a failure value.")
        return
    }
    #expect(message.contains("Cannot reach Ollama"))
}

/// Records the instant the assembler was called with.
private actor Recorder {
    private(set) var value: Date?
    func record(_ date: Date) { value = date }
}
