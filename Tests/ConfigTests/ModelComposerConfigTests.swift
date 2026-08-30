import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-250 / NIC-252: the composition prompt and its generation budget as configuration.
///
/// The prompt lives in a file rather than in Swift because two consumers read it — the host
/// composer and `evals/run-report.mjs`. A gate that measures a different prompt from the one that
/// ships is not a gate, so the rules protected here are the ones that would let the two drift or
/// let a composer ship without the bounds a model needs: a report composed twice, a capability
/// profile nothing configures, and an output budget left to the runtime's judgement.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func errors(_ json: String) -> [CerebralHelmConfigValidationError] {
    ConfigValidator.modelComposersDocumentErrors(file: "models/composer.json", data: Data(json.utf8))
}

/// A config directory copied from the shipped one, so a test can remove or rewrite a single file
/// without touching the repository.
private func temporaryConfig() throws -> URL {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cerebral-model-composer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(
        at: repositoryRoot().appendingPathComponent("config", isDirectory: true), to: temporary
    )
    return temporary
}

// MARK: - The shipped catalog

@Test("the shipped catalog composes the daily brief through a configured profile")
func shippedComposerResolves() throws {
    let configDirectory = repositoryRoot().appendingPathComponent("config", isDirectory: true)

    guard case let .valid(validated) = ConfigValidator.validate(configDirectory: configDirectory) else {
        Issue.record("The shipped config no longer validates.")
        return
    }
    let catalog = try #require(validated.modelComposers)
    let brief = try #require(catalog.composerReports.first { $0.composerReportID == "daily-brief" })

    // Profile notes are `sensitivity: sensitive` / `cloudPolicy: deny`, so the brief composes on
    // the profile that is a policy statement rather than a capability: never leaves this machine.
    #expect(brief.modelProfileID == .local)

    // AC-11. A grammar over an under-constrained schema emits valid output forever — measured at
    // 123 blocks and 15,655 tokens before the context wall truncated the document mid-token.
    #expect(brief.composerMaxOutputTokens > 0)
    #expect(brief.composerMaxBlocks > 0)

    // The system prompt is shared so every composer hits one prefix-cache prefix; the per-report
    // editorial direction is what varies.
    #expect(!catalog.composerSystemPrompt.isEmpty)
    #expect(!brief.composerInstruction.isEmpty)
}

@Test("every shipped composer names a profile that does not deliberate")
func shippedComposersDoNotThink() throws {
    let configDirectory = repositoryRoot().appendingPathComponent("config", isDirectory: true)

    guard case let .valid(validated) = ConfigValidator.validate(configDirectory: configDirectory) else {
        Issue.record("The shipped config no longer validates.")
        return
    }
    let profiles = try #require(validated.modelProfiles.map(ModelProfileCatalog.init))

    // Composition from an already-typed snapshot is rendering, not reasoning. Left to deliberate,
    // the model spent 3,000-4,200 tokens before emitting a short brief — 79-130 s against 9-17 s.
    // Asserted on the shipped configuration rather than encoded as a validator rule: `deep` exists
    // and legitimately thinks, it simply has no business composing a report.
    for composer in validated.modelComposers?.composerReports ?? [] {
        let resolved = try #require(
            ModelCapabilityProfile(rawValue: composer.modelProfileID.rawValue).flatMap(profiles.resolve)
        )
        #expect(
            resolved.thinking == false,
            "Report \"\(composer.composerReportID)\" composes on a profile that deliberates."
        )
    }
}

@Test("a machine that composes no report with a model is still a valid machine")
func absentComposerIsNotAnError() throws {
    let temporary = try temporaryConfig()
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.removeItem(
        at: temporary.appendingPathComponent("models/composer.json")
    )

    switch ConfigValidator.validate(configDirectory: temporary) {
    case let .valid(validated):
        #expect(validated.modelComposers == nil)
        // The profile catalog beside it is untouched: the two families are addressed by filename,
        // so removing one never disturbs the other.
        #expect(validated.modelProfiles != nil)
    case let .invalid(found):
        Issue.record("An absent composer catalog must not invalidate config: \(found.map(\.message))")
    }
}

// MARK: - One entry per report

@Test("a report composed twice is rejected rather than resolved by array order")
func duplicateReportIsRejected() {
    let found = errors("""
    {
      "schemaVersion": "1.0.0",
      "composerSystemPrompt": "Compose report documents. Offer open-mail where it fits.",
      "composerActions": [
        { "composerActionId": "open-mail", "composerActionUse": "to reach his inbox" }
      ],
      "composerReports": [
        {"composerReportId":"daily-brief","modelProfileId":"local","composerInstruction":"One.","composerMaxOutputTokens":1200,"composerMaxBlocks":12},
        {"composerReportId":"daily-brief","modelProfileId":"fast","composerInstruction":"Two.","composerMaxOutputTokens":900,"composerMaxBlocks":8}
      ]
    }
    """)

    #expect(found.contains { $0.message.contains("composed more than once") })
}

// MARK: - The profile a composer names must exist

@Test("a composer naming an unconfigured profile is rejected at validation, not at composition")
func unconfiguredProfileIsRejected() throws {
    let temporary = try temporaryConfig()
    defer { try? FileManager.default.removeItem(at: temporary) }

    // `deep` is dropped from the catalog while the composer is repointed at it — the shape a
    // half-finished configuration edit actually takes.
    let composer = """
    {
      "schemaVersion": "1.0.0",
      "composerSystemPrompt": "Compose report documents. Offer open-mail where it fits.",
      "composerActions": [
        { "composerActionId": "open-mail", "composerActionUse": "to reach his inbox" }
      ],
      "composerReports": [
        {"composerReportId":"daily-brief","modelProfileId":"deep","composerInstruction":"Compose.","composerMaxOutputTokens":1200,"composerMaxBlocks":12}
      ]
    }
    """
    try Data(composer.utf8).write(to: temporary.appendingPathComponent("models/composer.json"))

    let profilesURL = temporary.appendingPathComponent("models/profiles.json")
    let catalog = try JSONDecoder().decode(
        CerebralHelmModelProfileCatalog.self, from: Data(contentsOf: profilesURL)
    )
    let trimmed = CerebralHelmModelProfileCatalog(
        extensions: catalog.extensions,
        modelProfiles: catalog.modelProfiles.filter { $0.id != .deep },
        residentBudgetGigabytes: catalog.residentBudgetGigabytes,
        schemaVersion: catalog.schemaVersion
    )
    try JSONEncoder().encode(trimmed).write(to: profilesURL)

    switch ConfigValidator.validate(configDirectory: temporary) {
    case .valid:
        Issue.record("A composer pointing at an unconfigured profile must not validate.")
    case let .invalid(found):
        #expect(found.contains { $0.message.contains("which models/profiles.json does not configure") })
    }
}

@Test("a composer catalog is inert, not invalid, on a machine with no profiles at all")
func composerWithoutAnyProfilesIsSkipped() throws {
    let temporary = try temporaryConfig()
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.removeItem(
        at: temporary.appendingPathComponent("models/profiles.json")
    )

    // The cross-reference is skipped rather than failing every composer: nothing can run here, but
    // that is a machine with no model configured, which the config layer treats as normal.
    switch ConfigValidator.validate(configDirectory: temporary) {
    case let .valid(validated):
        #expect(validated.modelProfiles == nil)
        #expect(validated.modelComposers != nil)
    case let .invalid(found):
        Issue.record("A composer with no profile catalog must not invalidate config: \(found.map(\.message))")
    }
}

// MARK: - Unknown keys

@Test("a composer smuggling a tool allowlist is rejected")
func unknownKeyIsRejected() {
    // The passive tier composes prose and proposals and executes nothing. A key that looks like it
    // grants capability must not be silently ignored by Codable, which accepts unknown keys.
    let found = errors("""
    {
      "schemaVersion": "1.0.0",
      "composerSystemPrompt": "Compose report documents. Offer open-mail where it fits.",
      "composerActions": [
        { "composerActionId": "open-mail", "composerActionUse": "to reach his inbox" }
      ],
      "composerReports": [
        {"composerReportId":"daily-brief","modelProfileId":"local","composerInstruction":"Compose.","composerMaxOutputTokens":1200,"composerMaxBlocks":12}
      ],
      "allowedToolIds": ["note.capture"]
    }
    """)

    #expect(!found.isEmpty)
}

@Test("a composer with no output cap is rejected")
func missingOutputCapIsRejected() {
    let found = errors("""
    {
      "schemaVersion": "1.0.0",
      "composerSystemPrompt": "Compose report documents. Offer open-mail where it fits.",
      "composerActions": [
        { "composerActionId": "open-mail", "composerActionUse": "to reach his inbox" }
      ],
      "composerReports": [
        {"composerReportId":"daily-brief","modelProfileId":"local","composerInstruction":"Compose.","composerMaxBlocks":12}
      ]
    }
    """)

    #expect(!found.isEmpty)
}
