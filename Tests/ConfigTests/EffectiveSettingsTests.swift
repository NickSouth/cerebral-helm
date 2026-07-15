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
        confirmAllActions: true,
        appearanceDensity: "compact",           // dropped from the snapshot — must not leak
        appearanceReducedMotion: true,
        appearanceAssistantName: "Aria",
        commandPaletteHotkey: "option-space",   // excluded from the snapshot — must not leak
        knowledgeRootReference: "primary-vault",
        windowsStoredByMode: true,
        mainDisplayID: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
        layoutDisplayID: "cgid-secondary-4k",
        modeColorsJSON: ##"{"executive.primary":"#ffd166","developer.secondary":"#7fc4dc"}"##
    )

    let snapshot = EffectiveSettings.resolve(stored: stored, configDefaultModeID: "executive")

    #expect(snapshot.defaultModeID == "developer")
    #expect(snapshot.confirmAllActions == true)
    #expect(snapshot.appearance.reducedMotion == true)
    #expect(snapshot.appearance.assistantName == "Aria")
    #expect(snapshot.modeColors["executive.primary"] == "#ffd166")
    #expect(snapshot.modeColors["developer.secondary"] == "#7fc4dc")
    #expect(snapshot.knowledge.rootReference == "primary-vault")
    #expect(snapshot.workspace.windowsStoredByMode == true)
    #expect(snapshot.workspace.mainDisplayID == "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    #expect(snapshot.workspace.layoutDisplayID == "cgid-secondary-4k")
    #expect(snapshot.schemaVersion == "1.0.0")
}

@Test("unset fields resolve to their documented defaults")
func unsetResolvesToDefaults() {
    let snapshot = EffectiveSettings.resolve(stored: StoredSettings(), configDefaultModeID: "executive")

    #expect(snapshot.defaultModeID == "executive")            // configured default
    #expect(snapshot.confirmAllActions == false)              // descriptor policy governs
    #expect(snapshot.appearance.reducedMotion == false)
    #expect(snapshot.appearance.assistantName == "Heimlich")  // the default identity
    #expect(snapshot.modeColors.isEmpty)                      // no overrides → shipped palette

    #expect(snapshot.knowledge.rootReference == nil)          // meaningful "no root chosen"
    #expect(snapshot.workspace.windowsStoredByMode == false)
    #expect(snapshot.workspace.mainDisplayID == "system-primary")
    #expect(snapshot.workspace.layoutDisplayID == "system-primary")  // unset → same as main
}

@Test("the effective knowledge root re-points to an override path, else the default (NIC-138)")
func knowledgeRootResolution() {
    let defaultRoot = URL(fileURLWithPath: "/var/state/knowledge")

    // Unset / blank → the environment default.
    #expect(EffectiveSettings.knowledgeRootURL(reference: nil, default: defaultRoot) == defaultRoot)
    #expect(EffectiveSettings.knowledgeRootURL(reference: "   ", default: defaultRoot) == defaultRoot)

    // Absolute path → used as given (standardized).
    #expect(
        EffectiveSettings.knowledgeRootURL(reference: "/Users/me/vault", default: defaultRoot)
            == URL(fileURLWithPath: "/Users/me/vault").standardizedFileURL
    )

    // A bare/relative reference resolves beside the default root, inside the workspace.
    #expect(
        EffectiveSettings.knowledgeRootURL(reference: "vault", default: defaultRoot)
            == URL(fileURLWithPath: "/var/state/vault").standardizedFileURL
    )
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
