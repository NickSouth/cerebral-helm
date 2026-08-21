import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-243: the model-profile catalog as configuration.
///
/// The rules worth protecting are the ones that would otherwise fail silently — a residency whose
/// idle window does not match its mode, a context cap left to the runtime's own judgement, and the
/// requirement that a machine with no model configured stays a perfectly valid machine.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func catalogData(_ json: String) -> Data { Data(json.utf8) }

private func errors(_ json: String) -> [CerebralHelmConfigValidationError] {
    ConfigValidator.modelProfilesDocumentErrors(file: "models/profiles.json", data: catalogData(json))
}

private let pinnedBalanced = """
{"id":"balanced","modelId":"qwen3.6:35b-mlx","runtimeId":"ollama","contextTokens":16384,"residency":"pinned","thinking":false}
"""

// MARK: - The shipped catalog

@Test("the shipped catalog loads and resolves every capability profile")
func shippedCatalogResolves() throws {
    let configDirectory = repositoryRoot().appendingPathComponent("config", isDirectory: true)

    guard case let .valid(validated) = ConfigValidator.validate(configDirectory: configDirectory) else {
        Issue.record("The shipped config no longer validates.")
        return
    }
    let catalog = try #require(validated.modelProfiles.map(ModelProfileCatalog.init))

    #expect(catalog.configuredProfiles == [.fast, .balanced, .deep, .local])

    let balanced = try #require(catalog.resolve(.balanced))
    #expect(balanced.modelID == "qwen3.6:35b-mlx")
    #expect(balanced.runtime == .ollama)
    #expect(balanced.contextTokens == 16_384)
    // The always-on surface pins; a ~70 s cold reload would otherwise be felt every time.
    #expect(balanced.residency == .pinned)
    #expect(balanced.thinking == false)

    let deep = try #require(catalog.resolve(.deep))
    // Deliberation is on in exactly one place, and that place is not composition.
    #expect(deep.thinking)
    #expect(deep.residency == .evictAfterUse)
    #expect(deep.timeout == .seconds(600))
}

@Test("a machine with no model configured is still a valid machine")
func absentCatalogIsNotAnError() throws {
    // No models/ directory at all: the config below is the shipped set minus that family.
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cerebral-model-profiles-\(UUID().uuidString)", isDirectory: true)
    let source = repositoryRoot().appendingPathComponent("config", isDirectory: true)
    try FileManager.default.copyItem(at: source, to: temporary)
    try FileManager.default.removeItem(at: temporary.appendingPathComponent("models", isDirectory: true))
    defer { try? FileManager.default.removeItem(at: temporary) }

    switch ConfigValidator.validate(configDirectory: temporary) {
    case let .valid(validated):
        #expect(validated.modelProfiles == nil)
    case let .invalid(found):
        Issue.record("An absent model catalog must not invalidate config: \(found.map(\.message))")
    }
}

// MARK: - Residency and its idle window must agree

@Test("a bounded profile with no idle window is rejected rather than silently defaulted")
func boundedNeedsAnIdleWindow() {
    let found = errors("""
    {"schemaVersion":"1.0.0","modelProfiles":[
      {"id":"fast","modelId":"m","runtimeId":"ollama","contextTokens":8192,"residency":"bounded","thinking":false}
    ]}
    """)
    #expect(found.count == 1)
    #expect(found.first?.field == "/modelProfiles/residencyIdleSeconds")
}

@Test("an idle window on a pinned profile is rejected — nothing would ever read it")
func pinnedRejectsAnIdleWindow() {
    let found = errors("""
    {"schemaVersion":"1.0.0","modelProfiles":[
      {"id":"balanced","modelId":"m","runtimeId":"ollama","contextTokens":16384,"residency":"pinned","residencyIdleSeconds":300,"thinking":false}
    ]}
    """)
    #expect(found.count == 1)
    #expect(found.first?.field == "/modelProfiles/residencyIdleSeconds")
}

@Test("a profile configured twice is rejected")
func duplicateProfileRejected() {
    let found = errors("""
    {"schemaVersion":"1.0.0","modelProfiles":[\(pinnedBalanced),\(pinnedBalanced)]}
    """)
    #expect(found.contains { $0.field == "/modelProfiles" })
}

@Test("a valid catalog produces no errors at all")
func validCatalogIsClean() {
    #expect(errors("""
    {"schemaVersion":"1.0.0","residentBudgetGigabytes":48,"modelProfiles":[\(pinnedBalanced)]}
    """).isEmpty)
}

// MARK: - Unknown keys (configuration must not smuggle in policy)

@Test("an unknown top-level key is rejected")
func unknownTopLevelKeyRejected() {
    let found = errors("""
    {"schemaVersion":"1.0.0","confirmAllActions":false,"modelProfiles":[\(pinnedBalanced)]}
    """)
    #expect(!found.isEmpty)
}

// MARK: - The persisted snapshot must survive the new field

@Test("a last-known-good snapshot written before model profiles existed still decodes")
func olderSnapshotStillDecodes() throws {
    // Exactly the shape persisted by every release up to now: no modelProfiles key.
    let legacy = Data("""
    {
      "defaults": {"schemaVersion":"1.0.0","defaultModeId":"executive","enabledAgentIds":[],"enabledToolIds":[]},
      "modes": [],
      "agents": [],
      "toolIDs": []
    }
    """.utf8)

    let decoded = try JSONDecoder().decode(ActiveConfig.self, from: legacy)

    #expect(decoded.modelProfiles == nil)
    #expect(decoded.modelProfileCatalog == nil)
    #expect(decoded.defaults.defaultModeID == "executive")
}
