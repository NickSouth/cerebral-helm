import Foundation

/// The durable user settings: the persisted values of the settings-patch contract
/// fields (FR-CFG-01/04). Every field is optional — `nil` means "never set", and
/// consumers fall back to the layered config defaults. Settings survive restarts
/// and updates; they are user-owned state (FR-UPD-01).
public struct StoredSettings: Equatable, Sendable {
    public var defaultModeID: String?
    /// "Ask before all actions": when true, policy raises every non-read-only action
    /// to require confirmation (a stricter-only tightening). `nil`/false = descriptor
    /// policy governs (NIC-137).
    public var confirmAllActions: Bool?
    public var appearanceDensity: String?
    public var appearanceReducedMotion: Bool?
    /// The assistant's display name across the dashboard. `nil` = never set, so the
    /// default identity (`Heimlich`) applies.
    public var appearanceAssistantName: String?
    public var commandPaletteHotkey: String?
    public var knowledgeRootReference: String?
    /// "Windows Stored by Mode": a mode switch hides the outgoing mode's
    /// applications and returns the incoming mode's stored ones (NIC-85).
    /// `nil`/false = mode switches never hide or return windows.
    public var windowsStoredByMode: Bool?
    /// The stable display id the shell hosts the *main* dashboard backdrop on —
    /// conversations and palette focus target it (NIC-120b). `nil`, an unknown
    /// id, or one no longer connected all degrade to the system primary display;
    /// the shell never errors on a stale value.
    public var mainDisplayID: String?
    /// The stable display id layout mode opens on and whose bottom bar shows the
    /// hotswap pill (NIC-142). `nil`, an unknown, or a disconnected id degrades to
    /// the main display, then the system primary; the shell never errors on it.
    public var layoutDisplayID: String?
    /// The raw JSON of the patch's `modeColors` map (token name → `#rrggbb`),
    /// preserved verbatim. `nil`/absent = no per-mode color overrides, so every
    /// mode uses its shipped palette (NIC-137).
    public var modeColorsJSON: String?
    /// The raw JSON of the patch's `extensions` object, preserved verbatim so
    /// unknown-but-safe user fields survive updates (FR-CFG-05).
    public var extensionsJSON: String?
    /// The raw JSON array of the user's tracked stock tickers (NIC-128), preserved
    /// verbatim. `nil`/absent = never set, so the shipped starter list applies; an
    /// explicit `[]` is a meaningful "cleared" state (distinct from unset).
    public var stockTickersJSON: String?
    /// The raw JSON of the patch's `calendarModeMap` (calendar id → mode id),
    /// preserved verbatim. `nil`/absent = no mappings, so every calendar's events
    /// fall to the default mode (Executive) at the resolver (NIC-126).
    public var calendarModeMapJSON: String?

    public init(
        defaultModeID: String? = nil,
        confirmAllActions: Bool? = nil,
        appearanceDensity: String? = nil,
        appearanceReducedMotion: Bool? = nil,
        appearanceAssistantName: String? = nil,
        commandPaletteHotkey: String? = nil,
        knowledgeRootReference: String? = nil,
        windowsStoredByMode: Bool? = nil,
        mainDisplayID: String? = nil,
        layoutDisplayID: String? = nil,
        modeColorsJSON: String? = nil,
        extensionsJSON: String? = nil,
        stockTickersJSON: String? = nil,
        calendarModeMapJSON: String? = nil
    ) {
        self.defaultModeID = defaultModeID
        self.confirmAllActions = confirmAllActions
        self.appearanceDensity = appearanceDensity
        self.appearanceReducedMotion = appearanceReducedMotion
        self.appearanceAssistantName = appearanceAssistantName
        self.commandPaletteHotkey = commandPaletteHotkey
        self.knowledgeRootReference = knowledgeRootReference
        self.windowsStoredByMode = windowsStoredByMode
        self.mainDisplayID = mainDisplayID
        self.layoutDisplayID = layoutDisplayID
        self.modeColorsJSON = modeColorsJSON
        self.extensionsJSON = extensionsJSON
        self.stockTickersJSON = stockTickersJSON
        self.calendarModeMapJSON = calendarModeMapJSON
    }
}

/// A typed settings-patch `changes` object. Built from an
/// already-validated (``SettingsPatchValidator``) payload dictionary; a present
/// field sets its value, an absent field leaves the stored value untouched. The
/// patch contract has no clear/reset semantics, so none exist here either.
public struct SettingsChanges: Equatable, Sendable {
    public var defaultModeID: String?
    public var confirmAllActions: Bool?
    public var appearanceDensity: String?
    public var appearanceReducedMotion: Bool?
    public var appearanceAssistantName: String?
    public var commandPaletteHotkey: String?
    public var knowledgeRootReference: String?
    public var windowsStoredByMode: Bool?
    public var mainDisplayID: String?
    /// The stable display id layout mode opens on (NIC-142). See `StoredSettings`.
    public var layoutDisplayID: String?
    /// When present, replaces the stored `modeColors` map wholesale (token name → hex).
    public var modeColorsJSON: String?
    /// When present, replaces the stored `extensions` object wholesale.
    public var extensionsJSON: String?
    /// When present, replaces the stored ticker list wholesale (NIC-128). A JSON array
    /// string of normalized (uppercased, deduped) symbols; `"[]"` clears the list.
    public var stockTickersJSON: String?
    /// When present, replaces the stored calendar→mode map wholesale (NIC-126). A JSON
    /// object string (calendar id → mode id); `"{}"` clears the mappings.
    public var calendarModeMapJSON: String?

    public init(
        defaultModeID: String? = nil,
        confirmAllActions: Bool? = nil,
        appearanceDensity: String? = nil,
        appearanceReducedMotion: Bool? = nil,
        appearanceAssistantName: String? = nil,
        commandPaletteHotkey: String? = nil,
        knowledgeRootReference: String? = nil,
        windowsStoredByMode: Bool? = nil,
        mainDisplayID: String? = nil,
        layoutDisplayID: String? = nil,
        modeColorsJSON: String? = nil,
        extensionsJSON: String? = nil,
        stockTickersJSON: String? = nil,
        calendarModeMapJSON: String? = nil
    ) {
        self.defaultModeID = defaultModeID
        self.confirmAllActions = confirmAllActions
        self.appearanceDensity = appearanceDensity
        self.appearanceReducedMotion = appearanceReducedMotion
        self.appearanceAssistantName = appearanceAssistantName
        self.commandPaletteHotkey = commandPaletteHotkey
        self.knowledgeRootReference = knowledgeRootReference
        self.windowsStoredByMode = windowsStoredByMode
        self.mainDisplayID = mainDisplayID
        self.layoutDisplayID = layoutDisplayID
        self.modeColorsJSON = modeColorsJSON
        self.extensionsJSON = extensionsJSON
        self.stockTickersJSON = stockTickersJSON
        self.calendarModeMapJSON = calendarModeMapJSON
    }

    /// Extracts the known contract fields from a validated `changes` dictionary.
    /// Unknown keys were already rejected by the validator; this only lifts the
    /// allowlisted fields into a Sendable value.
    public init(validatedChanges changes: [String: Any]) {
        defaultModeID = changes["defaultModeId"] as? String
        confirmAllActions = changes["confirmAllActions"] as? Bool
        if let appearance = changes["appearance"] as? [String: Any] {
            appearanceDensity = appearance["density"] as? String
            appearanceReducedMotion = appearance["reducedMotion"] as? Bool
            appearanceAssistantName = appearance["assistantName"] as? String
        }
        if let hotkeys = changes["hotkeys"] as? [String: Any] {
            commandPaletteHotkey = hotkeys["commandPalette"] as? String
        }
        if let knowledge = changes["knowledge"] as? [String: Any] {
            knowledgeRootReference = knowledge["rootReference"] as? String
        }
        if let workspace = changes["workspace"] as? [String: Any] {
            windowsStoredByMode = workspace["windowsStoredByMode"] as? Bool
            mainDisplayID = workspace["mainDisplayId"] as? String
            layoutDisplayID = workspace["layoutDisplayId"] as? String
        }
        if let modeColors = changes["modeColors"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: modeColors, options: [.sortedKeys]) {
            modeColorsJSON = String(decoding: data, as: UTF8.self)
        }
        if let extensions = changes["extensions"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: extensions, options: [.sortedKeys]) {
            extensionsJSON = String(decoding: data, as: UTF8.self)
        }
        if let calendarModeMap = changes["calendarModeMap"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: calendarModeMap, options: [.sortedKeys]) {
            // Serialized with sorted keys so an unchanged map round-trips to identical bytes.
            calendarModeMapJSON = String(decoding: data, as: UTF8.self)
        }
        if let stocks = changes["stocks"] as? [String: Any],
           let rawTickers = stocks["tickers"] as? [Any] {
            // Normalize once at the write boundary so the stored value is clean regardless of
            // client: uppercase, trim, drop blanks, and dedupe (order-preserving). An empty
            // (or all-blank) list serializes to "[]" — a meaningful "cleared" state, not unset.
            var seen: Set<String> = []
            let normalized = rawTickers
                .compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            if let data = try? JSONSerialization.data(withJSONObject: normalized, options: []) {
                stockTickersJSON = String(decoding: data, as: UTF8.self)
            }
        }
    }

    /// Whether the patch carries any persistable field.
    public var isEmpty: Bool {
        defaultModeID == nil && confirmAllActions == nil && appearanceDensity == nil
            && appearanceReducedMotion == nil && appearanceAssistantName == nil
            && commandPaletteHotkey == nil && knowledgeRootReference == nil
            && windowsStoredByMode == nil && mainDisplayID == nil && layoutDisplayID == nil
            && modeColorsJSON == nil && extensionsJSON == nil && stockTickersJSON == nil
            && calendarModeMapJSON == nil
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
