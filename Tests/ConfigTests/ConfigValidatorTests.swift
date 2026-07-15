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

// MARK: - Authored layout (NIC-142)

private func developerModeWithLayout(_ layoutJSON: String) -> Data {
    """
    {
      "id": "developer",
      "label": "Developer",
      "theme": { "accentPrimary": "developer.primary", "accentSecondary": "developer.secondary" },
      "quickApps": ["vscode"],
      "quickActions": ["open-developer-layout","open-workspace","run-tests","search-notes","git-status","open-terminal","review-pull-requests","capture-note"],
      "widgets": { "left": "project-git-status", "right": "repositories" },
      "layout": \(layoutJSON)
    }
    """.data(using: .utf8)!
}

@Test("the shipped developer mode carries an authored layout with a quick-toggle slot")
func shippedDeveloperLayoutPresent() {
    let configDirectory = repositoryRoot().appendingPathComponent("config", isDirectory: true)
    guard case let .valid(validated) = ConfigValidator.validate(configDirectory: configDirectory),
          let developer = validated.modes.first(where: { $0.id == "developer" })
    else {
        Issue.record("developer mode did not validate")
        return
    }
    #expect(developer.layout != nil)
    #expect(developer.layout?.windows.isEmpty == false)
    #expect(developer.layout?.quickToggle?.targets.isEmpty == false)
}

@Test("a well-formed layout with a quick-toggle slot validates")
func validLayoutAccepted() {
    let data = developerModeWithLayout(#"""
    { "display": "primary",
      "windows": [ { "ref": "claude-desktop", "kind": "app", "frame": "right-third" } ],
      "quickToggle": { "frame": "left-two-thirds", "targets": [ { "ref": "vscode", "kind": "app" }, { "ref": "github", "kind": "url" } ] } }
    """#)
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: data)
    #expect(errors.isEmpty, "unexpected: \(errors.map { "\($0.field): \($0.message)" })")
}

@Test("a layout window with a frame outside the named vocabulary is rejected")
func layoutInvalidFrameRejected() throws {
    let data = try fixtureData("invalid/config/modes/layout-invalid-frame.json")
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/layout-invalid-frame.json", data: data)
    #expect(errors.contains { $0.field.contains("frame") || $0.message.lowercased().contains("frame") })
}

@Test("a layout with no windows is rejected")
func layoutEmptyWindowsRejected() {
    let data = developerModeWithLayout(#"{ "display": "primary", "windows": [] }"#)
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout/windows" })
}

@Test("a layout with more than eight windows is rejected")
func layoutTooManyWindowsRejected() {
    let windows = (0..<9)
        .map { #"{ "ref": "app-\#($0)", "kind": "app", "frame": "full" }"# }
        .joined(separator: ",")
    let data = developerModeWithLayout(#"{ "display": "primary", "windows": [\#(windows)] }"#)
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout/windows" && $0.message.contains("at most 8") })
}

@Test("a quick-toggle slot with no targets is rejected")
func layoutEmptyTargetsRejected() {
    let data = developerModeWithLayout(#"""
    { "display": "primary",
      "windows": [ { "ref": "vscode", "kind": "app", "frame": "left-two-thirds" } ],
      "quickToggle": { "frame": "left-two-thirds", "targets": [] } }
    """#)
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout/quickToggle/targets" })
}

@Test("a quick-toggle slot with duplicate targets is rejected")
func layoutDuplicateTargetsRejected() {
    let data = developerModeWithLayout(#"""
    { "display": "primary",
      "windows": [ { "ref": "vscode", "kind": "app", "frame": "left-two-thirds" } ],
      "quickToggle": { "frame": "left-two-thirds", "targets": [ { "ref": "github", "kind": "url" }, { "ref": "github", "kind": "url" } ] } }
    """#)
    let errors = ConfigValidator.modeDocumentErrors(file: "modes/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout/quickToggle/targets" && $0.message.contains("duplicate") })
}

@Test("an override carrying a valid layout validates (NIC-142)")
func overrideLayoutAccepted() {
    let data = Data(#"""
    { "schemaVersion": "1.0.0", "id": "developer",
      "layout": { "display": "primary",
        "windows": [ { "ref": "claude-desktop", "kind": "app", "frame": "right-third" } ],
        "quickToggle": { "frame": "left-two-thirds", "targets": [ { "ref": "vscode", "kind": "app" } ] } } }
    """#.utf8)
    #expect(ConfigValidator.overrideDocumentErrors(file: "overrides/developer.json", data: data).isEmpty)
}

@Test("an override with a structurally invalid layout is rejected")
func overrideLayoutStructurallyInvalidRejected() {
    let data = Data(#"""
    { "schemaVersion": "1.0.0", "id": "developer",
      "layout": { "display": "primary", "windows": [] } }
    """#.utf8)
    let errors = ConfigValidator.overrideDocumentErrors(file: "overrides/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout/windows" })
}

@Test("an override whose layout does not match the schema is rejected")
func overrideLayoutMalformedRejected() {
    let data = Data(#"""
    { "schemaVersion": "1.0.0", "id": "developer",
      "layout": { "display": "primary", "windows": [ { "ref": "vscode", "kind": "app", "frame": "left-quarter" } ] } }
    """#.utf8)
    let errors = ConfigValidator.overrideDocumentErrors(file: "overrides/developer.json", data: data)
    #expect(errors.contains { $0.field == "/layout" || $0.field.contains("layout") })
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
