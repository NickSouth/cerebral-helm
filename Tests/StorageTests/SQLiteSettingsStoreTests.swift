import Foundation
import Testing

import CerebralCore
import CerebralShared
import CerebralStorage

/// FR-CFG-04: durable settings persistence. Patches merge — present fields
/// overwrite, absent fields survive — and unknown-but-safe `extensions` content
/// is preserved verbatim (FR-CFG-05).

private func makeStore() throws -> SQLiteSettingsStore {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return SQLiteSettingsStore(database: db)
}

@Test("a store with no saved row loads the empty settings")
func emptyStoreLoadsEmptySettings() throws {
    let store = try makeStore()
    #expect(try store.load() == StoredSettings())
}

@Test("applied fields round-trip")
func appliedFieldsRoundTrip() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(
        defaultModeID: "developer",
        confirmAllActions: true,
        appearanceDensity: "compact",
        appearanceReducedMotion: true,
        appearanceAssistantName: "Aria",
        commandPaletteHotkey: "cmd+shift+space",
        knowledgeRootReference: "workspace",
        windowsStoredByMode: true,
        modeColorsJSON: ##"{"executive.primary":"#ffd166"}"##,
        extensionsJSON: #"{"x-theme-lab":{"glow":2}}"#
    ))

    let loaded = try store.load()
    #expect(loaded.defaultModeID == "developer")
    #expect(loaded.confirmAllActions == true)
    #expect(loaded.appearanceDensity == "compact")
    #expect(loaded.appearanceReducedMotion == true)
    #expect(loaded.appearanceAssistantName == "Aria")
    #expect(loaded.modeColorsJSON == ##"{"executive.primary":"#ffd166"}"##)
    #expect(loaded.commandPaletteHotkey == "cmd+shift+space")
    #expect(loaded.knowledgeRootReference == "workspace")
    #expect(loaded.windowsStoredByMode == true)
    #expect(loaded.extensionsJSON == #"{"x-theme-lab":{"glow":2}}"#)
}

@Test("the windows-stored-by-mode toggle round-trips and merges like every field")
func windowsStoredByModeRoundTrips() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(windowsStoredByMode: true))
    #expect(try store.load().windowsStoredByMode == true)

    // Turning it off is a value, not an absence; unrelated fields survive.
    try store.apply(SettingsChanges(defaultModeID: "school"))
    try store.apply(SettingsChanges(windowsStoredByMode: false))
    let loaded = try store.load()
    #expect(loaded.windowsStoredByMode == false)
    #expect(loaded.defaultModeID == "school")
}

@Test("the main-display id round-trips and merges like every field (NIC-120b)")
func mainDisplayIDRoundTrips() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(mainDisplayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))
    #expect(try store.load().mainDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    // Unrelated patches preserve it; a later patch replaces it.
    try store.apply(SettingsChanges(defaultModeID: "school"))
    #expect(try store.load().mainDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    try store.apply(SettingsChanges(mainDisplayID: "system-primary"))
    let loaded = try store.load()
    #expect(loaded.mainDisplayID == "system-primary")
    #expect(loaded.defaultModeID == "school")
}

@Test("the layout-display id round-trips and merges like every field (NIC-142)")
func layoutDisplayIDRoundTrips() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(layoutDisplayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))
    #expect(try store.load().layoutDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    // Unrelated patches preserve it; a later patch replaces it; it is independent
    // of the main-display id (both can hold different displays at once).
    try store.apply(SettingsChanges(mainDisplayID: "system-primary"))
    var loaded = try store.load()
    #expect(loaded.layoutDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    #expect(loaded.mainDisplayID == "system-primary")
    try store.apply(SettingsChanges(layoutDisplayID: "system-primary"))
    loaded = try store.load()
    #expect(loaded.layoutDisplayID == "system-primary")
}

@Test("the assistant name round-trips and merges like every field (NIC-137)")
func assistantNameRoundTrips() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(appearanceAssistantName: "Aria"))
    #expect(try store.load().appearanceAssistantName == "Aria")

    // An unrelated patch preserves it; a later patch replaces it.
    try store.apply(SettingsChanges(defaultModeID: "school"))
    #expect(try store.load().appearanceAssistantName == "Aria")
    try store.apply(SettingsChanges(appearanceAssistantName: "Nova"))
    let loaded = try store.load()
    #expect(loaded.appearanceAssistantName == "Nova")
    #expect(loaded.defaultModeID == "school")
}

@Test("per-mode color overrides round-trip and merge like every field (NIC-137)")
func modeColorsRoundTrip() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(modeColorsJSON: ##"{"executive.primary":"#ffd166"}"##))
    #expect(try store.load().modeColorsJSON == ##"{"executive.primary":"#ffd166"}"##)

    // An unrelated patch preserves it; a later patch replaces the map wholesale.
    try store.apply(SettingsChanges(defaultModeID: "school"))
    #expect(try store.load().modeColorsJSON == ##"{"executive.primary":"#ffd166"}"##)
    try store.apply(SettingsChanges(modeColorsJSON: ##"{"developer.secondary":"#7fc4dc"}"##))
    let loaded = try store.load()
    #expect(loaded.modeColorsJSON == ##"{"developer.secondary":"#7fc4dc"}"##)
    #expect(loaded.defaultModeID == "school")
}

@Test("a partial patch preserves every unrelated stored field")
func partialPatchPreservesOtherFields() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(defaultModeID: "developer", appearanceReducedMotion: false))
    try store.apply(SettingsChanges(appearanceDensity: "comfortable"))

    let loaded = try store.load()
    #expect(loaded.defaultModeID == "developer")
    #expect(loaded.appearanceDensity == "comfortable")
    #expect(loaded.appearanceReducedMotion == false)
}

@Test("a present field overwrites; false is a value, not an absence")
func presentFieldOverwrites() throws {
    let store = try makeStore()
    try store.apply(SettingsChanges(defaultModeID: "developer", appearanceReducedMotion: true))
    try store.apply(SettingsChanges(defaultModeID: "school", appearanceReducedMotion: false))

    let loaded = try store.load()
    #expect(loaded.defaultModeID == "school")
    #expect(loaded.appearanceReducedMotion == false)
}

@Test("SettingsChanges lifts the allowlisted fields from a validated changes object")
func settingsChangesLiftsValidatedFields() {
    let changes = SettingsChanges(validatedChanges: [
        "defaultModeId": "entertainment",
        "confirmAllActions": true,
        "appearance": ["density": "compact", "reducedMotion": true, "assistantName": "Aria"],
        "hotkeys": ["commandPalette": "cmd+space"],
        "knowledge": ["rootReference": "vault"],
        "modeColors": ["executive.primary": "#ffd166"],
        "extensions": ["x-lab": ["on": true]],
    ])
    #expect(changes.defaultModeID == "entertainment")
    #expect(changes.confirmAllActions == true)
    #expect(changes.appearanceDensity == "compact")
    #expect(changes.appearanceReducedMotion == true)
    #expect(changes.appearanceAssistantName == "Aria")
    #expect(changes.modeColorsJSON?.contains("executive.primary") == true)
    #expect(changes.commandPaletteHotkey == "cmd+space")
    #expect(changes.knowledgeRootReference == "vault")
    #expect(changes.extensionsJSON?.contains("x-lab") == true)
    #expect(!changes.isEmpty)
    #expect(SettingsChanges(validatedChanges: [:]).isEmpty)
}

@Test("settings persist across connections to the same file database")
func settingsPersistAcrossConnections() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-settings-\(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("cerebral.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let db = try SQLiteDatabase(location: .file(url))
        _ = try SchemaMigrator().migrate(db)
        try SQLiteSettingsStore(database: db).apply(SettingsChanges(defaultModeID: "school"))
    }

    let reopened = try SQLiteDatabase(location: .file(url))
    #expect(try SQLiteSettingsStore(database: reopened).load().defaultModeID == "school")
}
