import Foundation
import CerebralContracts

/// The validated configuration layer set produced by ``ConfigValidator``.
///
/// This is a *single* validated set of documents (defaults + modes + agents +
/// tool ids). Layering immutable defaults under user/session overrides and
/// activating a last-known-good snapshot is owned by the config loader
/// (NIC-36 part 2) and builds on top of this primitive.
public struct ValidatedConfig {
    public let defaults: CerebralHelmApplicationDefaults
    public let modes: [CerebralHelmModeConfig]
    public let agents: [CerebralHelmAgentSurfaceConfig]
    public let toolIDs: [String]
    /// Which model serves each capability profile (NIC-243), or nil when this machine ships no
    /// `config/models/profiles.json`. Optional and defaulted so a configuration with no model
    /// attached stays exactly as valid as it is today.
    public let modelProfiles: CerebralHelmModelProfileCatalog?

    public init(
        defaults: CerebralHelmApplicationDefaults,
        modes: [CerebralHelmModeConfig],
        agents: [CerebralHelmAgentSurfaceConfig],
        toolIDs: [String],
        modelProfiles: CerebralHelmModelProfileCatalog? = nil
    ) {
        self.defaults = defaults
        self.modes = modes
        self.agents = agents
        self.toolIDs = toolIDs
        self.modelProfiles = modelProfiles
    }
}

/// The result of validating a configuration directory.
public enum ConfigValidationOutcome {
    case valid(ValidatedConfig)
    case invalid([CerebralHelmConfigValidationError])
}

/// Validates CerebralHelm configuration before activation (FR-CFG-02).
///
/// Produces structured ``CerebralHelmConfigValidationError`` values that name the
/// offending file, field (JSON pointer), expected type, a human message, and a
/// remediation — never throwing on invalid input, so a caller can surface every
/// problem at once and keep the last-known-good configuration active.
///
/// Swift `Codable` silently ignores unknown keys, so strict decoding alone would
/// accept a mode that smuggles in a `riskOverrides` field. Configuration must
/// never weaken deterministic risk policy, so unknown top-level keys are an
/// explicit hard error here, mirroring the schemas' `additionalProperties: false`.
public enum ConfigValidator {
    /// Error documents are themselves versioned; this is the current revision.
    public static let schemaVersion = "1.0.0"

    // Allowed top-level keys per document type, mirroring the JSON Schemas under
    // packages/contracts/schemas/config. `x-` extension keys live *inside* the
    // `extensions` object, not at the top level, so the top-level set is fixed.
    // `ConfigSchemaSurfaceTests` asserts these stay in sync with the schemas.
    static let defaultsKeys: Set<String> = [
        "schemaVersion", "defaultModeId", "enabledAgentIds", "enabledToolIds", "extensions"
    ]
    static let modeKeys: Set<String> = [
        "id", "label", "theme", "quickApps", "quickActions", "widgets",
        "projectHints", "calendarProfile", "newsProfile", "greeting", "layoutId", "layout", "extensions"
    ]
    static let agentKeys: Set<String> = [
        "id", "label", "status", "summary", "allowedKnowledgeRoots", "allowedToolIds", "extensions"
    ]
    static let modelProfileCatalogKeys: Set<String> = [
        "schemaVersion", "residentBudgetGigabytes", "modelProfiles", "extensions"
    ]
    static let overrideKeys: Set<String> = [
        "schemaVersion", "id", "quickApps", "layout", "extensions"
    ]

    // MARK: - Directory orchestration

    /// Validates the configuration rooted at `configDirectory` (the `config/`
    /// folder): `defaults/app.json`, `modes/*.json`, `agents/*.json`, and the tool
    /// ids declared under `tools/*.json`.
    public static func validate(configDirectory: URL) -> ConfigValidationOutcome {
        var errors: [CerebralHelmConfigValidationError] = []

        // Defaults.
        let defaultsURL = configDirectory
            .appendingPathComponent("defaults", isDirectory: true)
            .appendingPathComponent("app.json")
        var defaults: CerebralHelmApplicationDefaults?
        if let data = readFile(defaultsURL) {
            let result = decodeDefaults(file: "defaults/app.json", data: data)
            defaults = result.value
            errors += result.errors
        } else {
            errors.append(makeError(
                file: "defaults/app.json",
                field: "/",
                expected: "a readable config file",
                message: "Application defaults file is missing or unreadable.",
                remediation: "Create config/defaults/app.json."
            ))
        }

        // Modes.
        var modes: [CerebralHelmModeConfig] = []
        for url in jsonFiles(in: configDirectory.appendingPathComponent("modes", isDirectory: true)) {
            let label = "modes/\(url.lastPathComponent)"
            guard let data = readFile(url) else {
                errors.append(unreadable(file: label))
                continue
            }
            let result = decodeMode(file: label, data: data)
            errors += result.errors
            if let mode = result.value { modes.append(mode) }
        }

        // Agents.
        var agents: [CerebralHelmAgentSurfaceConfig] = []
        for url in jsonFiles(in: configDirectory.appendingPathComponent("agents", isDirectory: true)) {
            let label = "agents/\(url.lastPathComponent)"
            guard let data = readFile(url) else {
                errors.append(unreadable(file: label))
                continue
            }
            let result = decodeAgent(file: label, data: data)
            errors += result.errors
            if let agent = result.value { agents.append(agent) }
        }

        // Tool ids. Two distinct sets live under `config/tools`:
        //   * the optional stricter-only OVERLAY files (`config/tools/*.json`), and
        //   * the authoritative tool DESCRIPTORS (`config/tools/descriptors/*.json`).
        // `ValidatedConfig.toolIDs` preserves the overlay ids (its established
        // semantics; the config loader carries it into `ActiveConfig`). The
        // `enabledToolIds` cross-reference, however, must resolve against the
        // authoritative descriptor set (ADR-003): an overlay is an optional
        // stricter-only subset, so an enabled tool that has a descriptor but no
        // overlay is valid and must not be flagged.
        let toolsDirectory = configDirectory.appendingPathComponent("tools", isDirectory: true)
        let toolResult = readToolIDs(in: toolsDirectory)
        errors += toolResult.errors
        let toolIDs = toolResult.ids
        let descriptorIDs = readDescriptorIDs(
            in: toolsDirectory.appendingPathComponent("descriptors", isDirectory: true)
        )

        // Model profiles (NIC-243). Deliberately optional: a machine with no model configured is
        // a valid machine, so an absent file is silence rather than an error. A file that IS
        // present must be correct — a half-configured model is worse than none.
        var modelProfiles: CerebralHelmModelProfileCatalog?
        let modelProfilesURL = configDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("profiles.json")
        if FileManager.default.fileExists(atPath: modelProfilesURL.path) {
            let label = "models/profiles.json"
            if let data = readFile(modelProfilesURL) {
                let result = decodeModelProfiles(file: label, data: data)
                errors += result.errors
                modelProfiles = result.value
            } else {
                errors.append(unreadable(file: label))
            }
        }

        // Cross-file references (only meaningful once defaults decoded).
        if let defaults {
            errors += crossReferenceErrors(
                defaults: defaults,
                modeIDs: Set(modes.map { $0.id }),
                agentIDs: Set(agents.map { $0.id }),
                toolIDs: Set(descriptorIDs)
            )
        }

        if errors.isEmpty, let defaults {
            return .valid(ValidatedConfig(
                defaults: defaults,
                modes: modes,
                agents: agents,
                toolIDs: toolIDs,
                modelProfiles: modelProfiles
            ))
        }
        return .invalid(errors)
    }

    // MARK: - Public document validators (fixture-test friendly)

    public static func defaultsDocumentErrors(file: String, data: Data) -> [CerebralHelmConfigValidationError] {
        decodeDefaults(file: file, data: data).errors
    }

    public static func modeDocumentErrors(file: String, data: Data) -> [CerebralHelmConfigValidationError] {
        decodeMode(file: file, data: data).errors
    }

    public static func agentDocumentErrors(file: String, data: Data) -> [CerebralHelmConfigValidationError] {
        decodeAgent(file: file, data: data).errors
    }

    public static func modelProfilesDocumentErrors(file: String, data: Data) -> [CerebralHelmConfigValidationError] {
        decodeModelProfiles(file: file, data: data).errors
    }

    public static func overrideDocumentErrors(file: String, data: Data) -> [CerebralHelmConfigValidationError] {
        decodeOverride(file: file, data: data).errors
    }

    /// Cross-file reference checks, exposed for in-memory testing without disk.
    public static func crossReferenceErrors(
        defaults: CerebralHelmApplicationDefaults,
        modeIDs: Set<String>,
        agentIDs: Set<String>,
        toolIDs: Set<String>
    ) -> [CerebralHelmConfigValidationError] {
        var errors: [CerebralHelmConfigValidationError] = []

        if !modeIDs.contains(defaults.defaultModeID) {
            errors.append(makeError(
                file: "defaults/app.json",
                field: "/defaultModeId",
                expected: "an existing mode id",
                message: "defaultModeId \"\(defaults.defaultModeID)\" does not match any mode.",
                remediation: "Set defaultModeId to a configured mode id."
            ))
        }
        for agentID in defaults.enabledAgentIDS where !agentIDs.contains(agentID) {
            errors.append(makeError(
                file: "defaults/app.json",
                field: "/enabledAgentIds",
                expected: "an existing agent id",
                message: "enabledAgentId \"\(agentID)\" does not match any agent.",
                remediation: "Remove \"\(agentID)\" or add the matching agent config."
            ))
        }
        for toolID in defaults.enabledToolIDS where !toolIDs.contains(toolID) {
            errors.append(makeError(
                file: "defaults/app.json",
                field: "/enabledToolIds",
                expected: "an existing tool id",
                message: "enabledToolId \"\(toolID)\" does not match any tool.",
                remediation: "Remove \"\(toolID)\" or add the matching tool config."
            ))
        }
        return errors
    }

    // MARK: - Per-document decode + structural checks

    private static func decodeDefaults(
        file: String, data: Data
    ) -> (value: CerebralHelmApplicationDefaults?, errors: [CerebralHelmConfigValidationError]) {
        decode(file: file, data: data, allowed: defaultsKeys, type: CerebralHelmApplicationDefaults.self) { _ in [] }
    }

    private static func decodeAgent(
        file: String, data: Data
    ) -> (value: CerebralHelmAgentSurfaceConfig?, errors: [CerebralHelmConfigValidationError]) {
        decode(file: file, data: data, allowed: agentKeys, type: CerebralHelmAgentSurfaceConfig.self) { _ in [] }
    }

    private static func decodeModelProfiles(
        file: String, data: Data
    ) -> (value: CerebralHelmModelProfileCatalog?, errors: [CerebralHelmConfigValidationError]) {
        decode(
            file: file,
            data: data,
            allowed: modelProfileCatalogKeys,
            type: CerebralHelmModelProfileCatalog.self
        ) { catalog in
            structuralModelProfileErrors(catalog, file: file)
        }
    }

    /// The rules the schema cannot state on its own: one entry per profile, and a residency whose
    /// idle window matches its mode. A `bounded` profile with no window would silently inherit a
    /// default, and an idle window on a `pinned` profile reads as meaningful when nothing consumes
    /// it — both are configuration that lies about what will happen.
    private static func structuralModelProfileErrors(
        _ catalog: CerebralHelmModelProfileCatalog,
        file: String
    ) -> [CerebralHelmConfigValidationError] {
        var errors: [CerebralHelmConfigValidationError] = []
        var seen: Set<ModelProfileID> = []

        for profile in catalog.modelProfiles {
            if !seen.insert(profile.id).inserted {
                errors.append(makeError(
                    file: file,
                    field: "/modelProfiles",
                    expected: "one entry per capability profile",
                    message: "Profile \"\(profile.id.rawValue)\" is configured more than once.",
                    remediation: "Remove the duplicate \"\(profile.id.rawValue)\" entry."
                ))
            }

            switch profile.residency {
            case .bounded where profile.residencyIdleSeconds == nil:
                errors.append(makeError(
                    file: file,
                    field: "/modelProfiles/residencyIdleSeconds",
                    expected: "an idle window, in seconds",
                    message: "Profile \"\(profile.id.rawValue)\" is bounded but states no residencyIdleSeconds.",
                    remediation: "Set residencyIdleSeconds, or choose pinned or evictAfterUse."
                ))
            case .pinned, .evictAfterUse:
                if profile.residencyIdleSeconds != nil {
                    errors.append(makeError(
                        file: file,
                        field: "/modelProfiles/residencyIdleSeconds",
                        expected: "no idle window",
                        message: "Profile \"\(profile.id.rawValue)\" is \(profile.residency.rawValue), so residencyIdleSeconds is never read.",
                        remediation: "Remove residencyIdleSeconds, or set residency to bounded."
                    ))
                }
            case .bounded:
                break
            }
        }
        return errors
    }

    private static func decodeOverride(
        file: String, data: Data
    ) -> (value: CerebralHelmModeOverride?, errors: [CerebralHelmConfigValidationError]) {
        decode(file: file, data: data, allowed: overrideKeys, type: CerebralHelmModeOverride.self) { override in
            structuralOverrideErrors(override, file: file)
        }
    }

    private static func decodeMode(
        file: String, data: Data
    ) -> (value: CerebralHelmModeConfig?, errors: [CerebralHelmConfigValidationError]) {
        decode(file: file, data: data, allowed: modeKeys, type: CerebralHelmModeConfig.self) { mode in
            structuralModeErrors(mode, file: file)
        }
    }

    /// Shared decode pipeline: unknown-key rejection, strict decode, then
    /// type-specific structural checks. Returns the decoded value when decoding
    /// succeeds (even alongside other errors) so callers can collect valid ids.
    private static func decode<T: Decodable>(
        file: String,
        data: Data,
        allowed: Set<String>,
        type: T.Type,
        structural: (T) -> [CerebralHelmConfigValidationError]
    ) -> (value: T?, errors: [CerebralHelmConfigValidationError]) {
        var errors: [CerebralHelmConfigValidationError] = []

        guard let keys = topLevelKeys(data) else {
            return (nil, [makeError(
                file: file,
                field: "/",
                expected: "a JSON object",
                message: "File is not a JSON object.",
                remediation: "Provide a JSON object that matches the schema."
            )])
        }
        errors += unknownKeyErrors(keys, allowed: allowed, file: file)

        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            errors += structural(value)
            return (value, errors)
        } catch {
            errors += decodingErrors(error, file: file)
            return (nil, errors)
        }
    }

    private static func structuralModeErrors(
        _ mode: CerebralHelmModeConfig, file: String
    ) -> [CerebralHelmConfigValidationError] {
        var errors: [CerebralHelmConfigValidationError] = []

        if mode.quickActions.count != 8 {
            errors.append(makeError(
                file: file,
                field: "/quickActions",
                expected: "exactly 8 entries",
                message: "Mode defines \(mode.quickActions.count) quick actions; exactly 8 are required.",
                remediation: "Provide exactly 8 quick action ids."
            ))
        }
        // Null slots are unconfigured ("add action") and may repeat; only the
        // configured (non-null) action ids must be unique.
        let configuredActions = mode.quickActions.compactMap { $0 }
        if Set(configuredActions).count != configuredActions.count {
            errors.append(makeError(
                file: file,
                field: "/quickActions",
                expected: "unique configured entries",
                message: "Quick actions contain a duplicate action id.",
                remediation: "Remove duplicate quick-action ids (unconfigured null slots may repeat)."
            ))
        }
        if mode.quickApps.count > 5 {
            errors.append(makeError(
                file: file,
                field: "/quickApps",
                expected: "0 to 5 entries",
                message: "Mode defines \(mode.quickApps.count) quick apps; at most 5 are allowed.",
                remediation: "Reduce quick apps to 5 or fewer."
            ))
        }
        if Set(mode.quickApps).count != mode.quickApps.count {
            errors.append(makeError(
                file: file,
                field: "/quickApps",
                expected: "unique entries",
                message: "Quick apps contain duplicates.",
                remediation: "Remove duplicate quick app ids."
            ))
        }
        // The design spec requires Developer, School, and Entertainment to expose
        // their own `open-<id>-layout` action; Executive's layout action is optional.
        if mode.id != "executive" {
            let layoutAction = "open-\(mode.id)-layout"
            if !configuredActions.contains(layoutAction) {
                errors.append(makeError(
                    file: file,
                    field: "/quickActions",
                    expected: "includes \"\(layoutAction)\"",
                    message: "Non-Executive mode \"\(mode.id)\" must include its layout action.",
                    remediation: "Add \"\(layoutAction)\" to quickActions."
                ))
            }
        }
        errors += structuralLayoutErrors(mode.layout, file: file)
        return errors
    }

    /// Structural checks for an authored window layout (NIC-142) that Swift
    /// `Codable` cannot enforce on its own: `Codable` ignores the schema's
    /// `minItems`/`maxItems`/`uniqueItems`, so a runtime config decoded here (as
    /// opposed to Ajv-validated fixtures) could still smuggle in an empty,
    /// oversized, or duplicate-target layout. The `window.arrange` tool caps a
    /// single arrangement at 8 entries, so both the static window set and the
    /// dynamic quick-toggle target set are bounded the same way. Enum/pattern
    /// constraints (frame, kind, display, ref) are already enforced by decoding.
    private static func structuralLayoutErrors(
        _ layout: Layout?, file: String
    ) -> [CerebralHelmConfigValidationError] {
        guard let layout else { return [] }
        var errors: [CerebralHelmConfigValidationError] = []

        if layout.windows.isEmpty {
            errors.append(makeError(
                file: file,
                field: "/layout/windows",
                expected: "1 to 8 windows",
                message: "Layout defines no windows.",
                remediation: "Add 1 to 8 window placements, or omit the layout."
            ))
        }
        if layout.windows.count > 8 {
            errors.append(makeError(
                file: file,
                field: "/layout/windows",
                expected: "at most 8 windows",
                message: "Layout defines \(layout.windows.count) windows; at most 8 are allowed.",
                remediation: "Reduce windows to 8 or fewer."
            ))
        }

        if let toggle = layout.quickToggle {
            if toggle.targets.isEmpty {
                errors.append(makeError(
                    file: file,
                    field: "/layout/quickToggle/targets",
                    expected: "1 to 8 targets",
                    message: "Quick-toggle slot defines no targets.",
                    remediation: "Add 1 to 8 toggle targets, or omit the quick-toggle slot."
                ))
            }
            if toggle.targets.count > 8 {
                errors.append(makeError(
                    file: file,
                    field: "/layout/quickToggle/targets",
                    expected: "at most 8 targets",
                    message: "Quick-toggle slot defines \(toggle.targets.count) targets; at most 8 are allowed.",
                    remediation: "Reduce toggle targets to 8 or fewer."
                ))
            }
            let targetKeys = toggle.targets.map { "\($0.ref)#\($0.kind.rawValue)" }
            if Set(targetKeys).count != targetKeys.count {
                errors.append(makeError(
                    file: file,
                    field: "/layout/quickToggle/targets",
                    expected: "unique targets",
                    message: "Quick-toggle targets contain duplicates.",
                    remediation: "Remove duplicate toggle targets."
                ))
            }
        }

        return errors
    }

    private static func structuralOverrideErrors(
        _ override: CerebralHelmModeOverride, file: String
    ) -> [CerebralHelmConfigValidationError] {
        var errors: [CerebralHelmConfigValidationError] = []
        if let apps = override.quickApps {
            if apps.count > 5 {
                errors.append(makeError(
                    file: file,
                    field: "/quickApps",
                    expected: "0 to 5 entries",
                    message: "Override defines \(apps.count) quick apps; at most 5 are allowed.",
                    remediation: "Reduce quick apps to 5 or fewer."
                ))
            }
            if Set(apps).count != apps.count {
                errors.append(makeError(
                    file: file,
                    field: "/quickApps",
                    expected: "unique entries",
                    message: "Override quick apps contain duplicates.",
                    remediation: "Remove duplicate quick app ids."
                ))
            }
        }
        // The override carries its layout opaquely (so the generated override type
        // stays flat); validate it structurally by decoding into the same typed
        // `Layout` the mode config uses (NIC-142).
        if let rawLayout = override.layout {
            if let layout = Layout.from(raw: rawLayout) {
                errors += structuralLayoutErrors(layout, file: file)
            } else {
                errors.append(makeError(
                    file: file,
                    field: "/layout",
                    expected: "a valid layout",
                    message: "Layout override does not match the layout schema.",
                    remediation: "Provide a layout with a display, 1-8 windows, and valid frames."
                ))
            }
        }
        return errors
    }

    // MARK: - Tool ids

    private static func readToolIDs(
        in directory: URL
    ) -> (ids: [String], errors: [CerebralHelmConfigValidationError]) {
        struct ToolIdentity: Decodable { let id: String }
        var ids: [String] = []
        var errors: [CerebralHelmConfigValidationError] = []
        for url in jsonFiles(in: directory) {
            let label = "tools/\(url.lastPathComponent)"
            guard let data = readFile(url) else {
                errors.append(unreadable(file: label))
                continue
            }
            if let identity = try? JSONDecoder().decode(ToolIdentity.self, from: data) {
                ids.append(identity.id)
            } else {
                errors.append(makeError(
                    file: label,
                    field: "/id",
                    expected: "a string tool id",
                    message: "Tool config is missing a string id.",
                    remediation: "Add a string \"id\" to the tool config."
                ))
            }
        }
        return (ids, errors)
    }

    /// Reads the tool ids from the authoritative descriptor set
    /// (`config/tools/descriptors/*.json`) for the `enabledToolIds` cross-reference.
    /// Descriptors are authoritative (ADR-003) and validated in full elsewhere
    /// (NIC-28); here only their `id` is needed, so a descriptor that fails to
    /// decode is simply omitted from the reference set rather than re-reported.
    private static func readDescriptorIDs(in directory: URL) -> [String] {
        struct ToolIdentity: Decodable { let id: String }
        var ids: [String] = []
        for url in jsonFiles(in: directory) {
            guard
                let data = readFile(url),
                let identity = try? JSONDecoder().decode(ToolIdentity.self, from: data)
            else { continue }
            ids.append(identity.id)
        }
        return ids
    }

    // MARK: - Helpers

    private static func topLevelKeys(_ data: Data) -> Set<String>? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return Set(object.keys)
    }

    private static func unknownKeyErrors(
        _ keys: Set<String>, allowed: Set<String>, file: String
    ) -> [CerebralHelmConfigValidationError] {
        keys.subtracting(allowed).sorted().map { key in
            makeError(
                file: file,
                field: "/\(key)",
                expected: "a supported property",
                message: "Unknown field \"\(key)\" is not allowed.",
                remediation: "Remove \"\(key)\"; only schema-defined fields and x- extensions are permitted."
            )
        }
    }

    private static func decodingErrors(
        _ error: Error, file: String
    ) -> [CerebralHelmConfigValidationError] {
        guard let decodingError = error as? DecodingError else {
            return [makeError(
                file: file,
                field: "/",
                expected: "valid JSON",
                message: error.localizedDescription,
                remediation: "Fix the JSON syntax."
            )]
        }

        switch decodingError {
        case let .typeMismatch(type, context):
            let expected = jsonTypeName(type)
            let field = jsonPointer(context.codingPath)
            return [makeError(
                file: file,
                field: field,
                expected: expected,
                message: "Field \(field) must be a \(expected).",
                remediation: "Change \(field) to a \(expected)."
            )]
        case let .valueNotFound(type, context):
            let expected = jsonTypeName(type)
            let field = jsonPointer(context.codingPath)
            return [makeError(
                file: file,
                field: field,
                expected: expected,
                message: "Field \(field) must not be null.",
                remediation: "Provide a \(expected) value for \(field)."
            )]
        case let .keyNotFound(key, context):
            let field = jsonPointer(context.codingPath + [key])
            return [makeError(
                file: file,
                field: field,
                expected: "present",
                message: "Required field \(field) is missing.",
                remediation: "Add \(field) to the document."
            )]
        case let .dataCorrupted(context):
            let field = jsonPointer(context.codingPath)
            return [makeError(
                file: file,
                field: field,
                expected: "a valid value",
                message: context.debugDescription,
                remediation: "Use a value allowed by the schema for \(field)."
            )]
        @unknown default:
            return [makeError(
                file: file,
                field: "/",
                expected: "valid configuration",
                message: "Configuration could not be decoded.",
                remediation: "Compare the document against the schema."
            )]
        }
    }

    /// Maps a `Codable` coding path to a JSON pointer (`/theme/accentPrimary`,
    /// `/quickActions/2`). The empty path is the document root, `/`.
    private static func jsonPointer(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "/" }
        return "/" + path.map { key in
            if let index = key.intValue { return String(index) }
            return key.stringValue
        }.joined(separator: "/")
    }

    private static func jsonTypeName(_ type: Any.Type) -> String {
        if type == String.self { return "string" }
        if type == Bool.self { return "boolean" }
        if type == Int.self || type == Double.self || type == Int64.self || type == UInt.self { return "number" }
        let described = String(describing: type)
        if described.contains("Array") { return "array" }
        if described.contains("Dictionary") { return "object" }
        return "value"
    }

    private static func readFile(_ url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func jsonFiles(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func unreadable(file: String) -> CerebralHelmConfigValidationError {
        makeError(
            file: file,
            field: "/",
            expected: "a readable config file",
            message: "Config file is unreadable.",
            remediation: "Ensure the file exists and is valid UTF-8 JSON."
        )
    }

    private static func makeError(
        file: String,
        field: String,
        expected: String,
        message: String,
        remediation: String
    ) -> CerebralHelmConfigValidationError {
        CerebralHelmConfigValidationError(
            expected: expected,
            field: field,
            file: file,
            message: message,
            remediation: remediation,
            schemaVersion: schemaVersion
        )
    }
}
