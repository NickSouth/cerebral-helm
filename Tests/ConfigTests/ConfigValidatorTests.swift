import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func fixtureData(_ relativePath: String) throws -> Data {
    let url = repositoryRoot()
        .appendingPathComponent("packages/contracts/fixtures", isDirectory: true)
        .appendingPathComponent(relativePath)
    return try Data(contentsOf: url)
}

// MARK: - Happy path

@Test("the shipped config directory validates as a coherent set")
func shippedConfigValidates() {
    let configDirectory = repositoryRoot().appendingPathComponent("config", isDirectory: true)

    switch ConfigValidator.validate(configDirectory: configDirectory) {
    case let .valid(validated):
        #expect(validated.modes.count == 4)
        #expect(validated.agents.count == 4)
        #expect(validated.modes.contains { $0.id == validated.defaults.defaultModeID })
    case let .invalid(errors):
        Issue.record("Expected valid config, got: \(errors.map { "\($0.file)\($0.field): \($0.message)" })")
    }
}

// MARK: - Unknown top-level keys (security: config must not weaken risk)

@Test("a mode carrying riskOverrides is rejected as an unknown field")
func riskOverrideRejected() throws {
    let data = try fixtureData("invalid/config/modes/risk-override.json")
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/risk-override.json", data: data)
    #expect(errors.contains { $0.field == "/riskOverrides" })
}

@Test("a mode with a non-extension unknown field is rejected")
func unsafeExtensionFieldRejected() throws {
    let data = try fixtureData("invalid/config/modes/unsafe-extension-field.json")
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/unsafe-extension-field.json", data: data)
    #expect(errors.contains { $0.field == "/unknownFutureField" })
}

// MARK: - New design-spec fields

@Test("an unknown calendarProfile enum value is rejected")
func unknownCalendarProfileRejected() throws {
    let data = try fixtureData("invalid/config/modes/unknown-calendar-profile.json")
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/unknown-calendar-profile.json", data: data)
    #expect(errors.contains { $0.field == "/calendarProfile" || $0.message.contains("CalendarProfile") })
}

@Test("a greeting missing its required fallback is rejected")
func greetingMissingFallbackRejected() throws {
    let data = try fixtureData("invalid/config/modes/greeting-missing-fallback.json")
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/greeting-missing-fallback.json", data: data)
    #expect(errors.contains { $0.field == "/greeting/fallback" })
}

// MARK: - Canonical error shape (matches valid/config/validation-error/mode-label-type.json)

@Test("a non-string mode label produces the /label string error shape")
func labelTypeProducesCanonicalError() {
    let json = Data(#"""
    {
      "id": "developer",
      "label": 5,
      "theme": { "accentPrimary": "developer.primary", "accentSecondary": "developer.secondary" },
      "quickApps": [],
      "quickActions": ["a", "b", "c", "d", "e", "f", "g", "h"],
      "widgets": { "left": "x", "right": "y" }
    }
    """#.utf8)

    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: json)
    let labelError = errors.first { $0.field == "/label" }

    #expect(labelError != nil)
    #expect(labelError?.expected == "string")
    #expect(labelError?.file == "modes/developer.json")
    #expect(labelError?.schemaVersion == "1.0.0")
}

// MARK: - Structural mode rules

@Test("a mode without exactly eight quick actions is rejected")
func quickActionsCountEnforced() {
    let json = Data(#"""
    {
      "id": "executive",
      "label": "Executive",
      "theme": { "accentPrimary": "executive.primary", "accentSecondary": "executive.secondary" },
      "quickApps": [],
      "quickActions": ["a", "b", "c"],
      "widgets": { "left": "x", "right": "y" }
    }
    """#.utf8)

    let errors = ConfigValidator.modeDocumentErrors(file: "modes/x.json", data: json)
    #expect(errors.contains { $0.field == "/quickActions" && $0.expected == "exactly 8 entries" })
}

@Test("nullable (unconfigured) quick-action slots are accepted")
func nullableQuickActionSlotsAccepted() {
    let json = Data(#"""
    {
      "id": "executive",
      "label": "Executive",
      "theme": { "accentPrimary": "executive.primary", "accentSecondary": "executive.secondary" },
      "quickApps": [],
      "quickActions": ["daily-brief", null, "capture-note", null, "check-system-status", null, null, null],
      "widgets": { "left": "x", "right": "y" }
    }
    """#.utf8)

    #expect(ConfigValidator.modeDocumentErrors(file: "modes/x.json", data: json).isEmpty)
}

@Test("a duplicate configured quick-action id is rejected (null slots may repeat)")
func duplicateConfiguredQuickActionRejected() {
    let json = Data(#"""
    {
      "id": "executive",
      "label": "Executive",
      "theme": { "accentPrimary": "executive.primary", "accentSecondary": "executive.secondary" },
      "quickApps": [],
      "quickActions": ["capture-note", "capture-note", null, null, null, null, null, null],
      "widgets": { "left": "x", "right": "y" }
    }
    """#.utf8)

    let errors = ConfigValidator.modeDocumentErrors(file: "modes/x.json", data: json)
    #expect(errors.contains { $0.field == "/quickActions" && $0.expected == "unique configured entries" })
}

@Test("a non-Executive mode missing its layout action is rejected")
func nonExecutiveLayoutActionEnforced() {
    let json = Data(#"""
    {
      "id": "developer",
      "label": "Developer",
      "theme": { "accentPrimary": "developer.primary", "accentSecondary": "developer.secondary" },
      "quickApps": [],
      "quickActions": ["a", "b", "c", "d", "e", "f", "g", "h"],
      "widgets": { "left": "x", "right": "y" }
    }
    """#.utf8)

    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: json)
    #expect(errors.contains { $0.field == "/quickActions" && $0.expected.contains("open-developer-layout") })
}

// MARK: - Cross-file references

@Test("cross-reference flags an unknown defaultModeId")
func crossReferenceFlagsUnknownDefaultMode() {
    let defaults = CerebralHelmApplicationDefaults(
        defaultModeID: "ghost",
        enabledAgentIDS: [],
        enabledToolIDS: [],
        extensions: nil,
        schemaVersion: "1.0.0"
    )

    let errors = ConfigValidator.crossReferenceErrors(
        defaults: defaults,
        modeIDs: ["executive"],
        agentIDs: [],
        toolIDs: []
    )

    #expect(errors.contains { $0.field == "/defaultModeId" })
}

@Test("cross-reference flags unknown enabled agent and tool ids")
func crossReferenceFlagsUnknownEnabledIDs() {
    let defaults = CerebralHelmApplicationDefaults(
        defaultModeID: "executive",
        enabledAgentIDS: ["ghost-agent"],
        enabledToolIDS: ["ghost.tool"],
        extensions: nil,
        schemaVersion: "1.0.0"
    )

    let errors = ConfigValidator.crossReferenceErrors(
        defaults: defaults,
        modeIDs: ["executive"],
        agentIDs: ["research-analyst"],
        toolIDs: ["app.open"]
    )

    #expect(errors.contains { $0.field == "/enabledAgentIds" })
    #expect(errors.contains { $0.field == "/enabledToolIds" })
}

// MARK: - Allow-list / schema drift guard

@Test("validator allowed-key sets stay in sync with the JSON Schemas")
func allowedKeysMatchSchemas() throws {
    func schemaProperties(_ name: String) throws -> Set<String> {
        let url = repositoryRoot()
            .appendingPathComponent("packages/contracts/schemas/config", isDirectory: true)
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let properties = object?["properties"] as? [String: Any]
        return Set((properties ?? [:]).keys)
    }

    #expect(try schemaProperties("app-defaults.schema.json") == ConfigValidator.defaultsKeys)
    #expect(try schemaProperties("mode.schema.json") == ConfigValidator.modeKeys)
    #expect(try schemaProperties("agent.schema.json") == ConfigValidator.agentKeys)
    #expect(try schemaProperties("mode-override.schema.json") == ConfigValidator.overrideKeys)
}
