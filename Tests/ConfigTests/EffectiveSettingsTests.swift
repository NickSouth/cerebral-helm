import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-141: ``EffectiveSettings`` is the single deterministic place the durable
/// settings resolve into the snapshot the settings UI reads. These tests pin the
/// resolution rules — stored value wins, unset falls back to the documented default,
/// and `defaultModeId` is the setting (stored, else configured, else `executive`),
/// never the active mode.

@Test("stored values win over every default")
func storedValuesWin() {
    let stored = StoredSettings(
        defaultModeID: "developer",
        appearanceDensity: "compact",           // dropped from the snapshot — must not leak
        appearanceReducedMotion: true,
        appearanceAssistantName: "Aria",
        commandPaletteHotkey: "option-space",   // excluded from the snapshot — must not leak
        knowledgeRootReference: "primary-vault",
        windowsStoredByMode: true,
        mainDisplayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    )

    let snapshot = EffectiveSettings.resolve(stored: stored, configDefaultModeID: "executive")

    #expect(snapshot.defaultModeID == "developer")
    #expect(snapshot.appearance.reducedMotion == true)
    #expect(snapshot.appearance.assistantName == "Aria")
    #expect(snapshot.knowledge.rootReference == "primary-vault")
    #expect(snapshot.workspace.windowsStoredByMode == true)
    #expect(snapshot.workspace.mainDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    #expect(snapshot.schemaVersion == "1.0.0")
}

@Test("unset fields resolve to their documented defaults")
func unsetResolvesToDefaults() {
    let snapshot = EffectiveSettings.resolve(stored: StoredSettings(), configDefaultModeID: "executive")

    #expect(snapshot.defaultModeID == "executive")            // configured default
    #expect(snapshot.appearance.reducedMotion == false)
    #expect(snapshot.appearance.assistantName == "Heimlich")  // the default identity

    #expect(snapshot.knowledge.rootReference == nil)          // meaningful "no root chosen"
    #expect(snapshot.workspace.windowsStoredByMode == false)
    #expect(snapshot.workspace.mainDisplayID == "system-primary")
}

@Test("defaultModeId falls back to `executive` when neither stored nor configured")
func defaultModeIDFinalFallback() {
    let snapshot = EffectiveSettings.resolve(stored: StoredSettings(), configDefaultModeID: nil)
    #expect(snapshot.defaultModeID == "executive")
}

@Test("a stored default mode wins over the configured default (it is the setting, not the active mode)")
func storedDefaultModeWinsOverConfigured() {
    let snapshot = EffectiveSettings.resolve(
        stored: StoredSettings(defaultModeID: "school"),
        configDefaultModeID: "executive"
    )
    #expect(snapshot.defaultModeID == "school")
}
