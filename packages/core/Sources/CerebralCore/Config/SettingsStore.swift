import Foundation

/// The durable user settings: the persisted values of the settings-patch contract
/// fields (FR-CFG-01/04). Every field is optional — `nil` means "never set", and
/// consumers fall back to the layered config defaults. Settings survive restarts
/// and updates; they are user-owned state (FR-UPD-01).
public struct StoredSettings: Equatable, Sendable {
    public var defaultModeID: String?
    public var appearanceDensity: String?
    public var appearanceReducedMotion: Bool?
    public var commandPaletteHotkey: String?
    public var knowledgeRootReference: String?
    /// The raw JSON of the patch's `extensions` object, preserved verbatim so
    /// unknown-but-safe user fields survive updates (FR-CFG-05).
    public var extensionsJSON: String?

    public init(
        defaultModeID: String? = nil,
        appearanceDensity: String? = nil,
        appearanceReducedMotion: Bool? = nil,
        commandPaletteHotkey: String? = nil,
        knowledgeRootReference: String? = nil,
        extensionsJSON: String? = nil
    ) {
        self.defaultModeID = defaultModeID
        self.appearanceDensity = appearanceDensity
        self.appearanceReducedMotion = appearanceReducedMotion
        self.commandPaletteHotkey = commandPaletteHotkey
        self.knowledgeRootReference = knowledgeRootReference
        self.extensionsJSON = extensionsJSON
    }
}

/// A typed settings-patch `changes` object. Built from an
/// already-validated (``SettingsPatchValidator``) payload dictionary; a present
/// field sets its value, an absent field leaves the stored value untouched. The
/// patch contract has no clear/reset semantics, so none exist here either.
public struct SettingsChanges: Equatable, Sendable {
    public var defaultModeID: String?
    public var appearanceDensity: String?
    public var appearanceReducedMotion: Bool?
    public var commandPaletteHotkey: String?
    public var knowledgeRootReference: String?
    /// When present, replaces the stored `extensions` object wholesale.
    public var extensionsJSON: String?

    public init(
        defaultModeID: String? = nil,
        appearanceDensity: String? = nil,
        appearanceReducedMotion: Bool? = nil,
        commandPaletteHotkey: String? = nil,
        knowledgeRootReference: String? = nil,
        extensionsJSON: String? = nil
    ) {
        self.defaultModeID = defaultModeID
        self.appearanceDensity = appearanceDensity
        self.appearanceReducedMotion = appearanceReducedMotion
        self.commandPaletteHotkey = commandPaletteHotkey
        self.knowledgeRootReference = knowledgeRootReference
        self.extensionsJSON = extensionsJSON
    }

    /// Extracts the known contract fields from a validated `changes` dictionary.
    /// Unknown keys were already rejected by the validator; this only lifts the
    /// allowlisted fields into a Sendable value.
    public init(validatedChanges changes: [String: Any]) {
        defaultModeID = changes["defaultModeId"] as? String
        if let appearance = changes["appearance"] as? [String: Any] {
            appearanceDensity = appearance["density"] as? String
            appearanceReducedMotion = appearance["reducedMotion"] as? Bool
        }
        if let hotkeys = changes["hotkeys"] as? [String: Any] {
            commandPaletteHotkey = hotkeys["commandPalette"] as? String
        }
        if let knowledge = changes["knowledge"] as? [String: Any] {
            knowledgeRootReference = knowledge["rootReference"] as? String
        }
        if let extensions = changes["extensions"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: extensions, options: [.sortedKeys]) {
            extensionsJSON = String(decoding: data, as: UTF8.self)
        }
    }

    /// Whether the patch carries any persistable field.
    public var isEmpty: Bool {
        defaultModeID == nil && appearanceDensity == nil && appearanceReducedMotion == nil
            && commandPaletteHotkey == nil && knowledgeRootReference == nil && extensionsJSON == nil
    }
}

/// Port for durable settings persistence. The SQLite adapter is the production
/// binding (ADR-006); tests may bind an in-memory fake.
public protocol SettingsStore: Sendable {
    /// The current stored settings; a store with no saved row returns the empty value.
    func load() throws -> StoredSettings

    /// Applies a validated patch: present fields overwrite, absent fields are
    /// preserved. Durable before return — a thrown error means nothing was saved.
    func apply(_ changes: SettingsChanges) throws
}
