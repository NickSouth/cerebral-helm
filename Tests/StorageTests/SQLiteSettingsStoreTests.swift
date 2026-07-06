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
        appearanceDensity: "compact",
        appearanceReducedMotion: true,
        commandPaletteHotkey: "cmd+shift+space",
        knowledgeRootReference: "workspace",
        extensionsJSON: #"{"x-theme-lab":{"glow":2}}"#
    ))

    let loaded = try store.load()
    #expect(loaded.defaultModeID == "developer")
    #expect(loaded.appearanceDensity == "compact")
    #expect(loaded.appearanceReducedMotion == true)
    #expect(loaded.commandPaletteHotkey == "cmd+shift+space")
    #expect(loaded.knowledgeRootReference == "workspace")
    #expect(loaded.extensionsJSON == #"{"x-theme-lab":{"glow":2}}"#)
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
        "appearance": ["density": "compact", "reducedMotion": true],
        "hotkeys": ["commandPalette": "cmd+space"],
        "knowledge": ["rootReference": "vault"],
        "extensions": ["x-lab": ["on": true]],
    ])
    #expect(changes.defaultModeID == "entertainment")
    #expect(changes.appearanceDensity == "compact")
    #expect(changes.appearanceReducedMotion == true)
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
