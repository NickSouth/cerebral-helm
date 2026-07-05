import Foundation
import KeyboardShortcuts

/// The configurable global shortcut that summons the command palette (NIC-75 /
/// FR-SHL-02).
///
/// Default: **⌥Space** (Option-Space) — deliberately not ⌘Space (Spotlight) or ⌃Space
/// (the common input-source toggle). `KeyboardShortcuts` is Carbon-backed
/// (`RegisterEventHotKey`), so this fires system-wide without the Accessibility
/// permission (ADR-001 / TECH-STACK). The user can rebind or disable it from settings
/// (a follow-on increment); the name string is the durable persistence key, so it must
/// stay stable across releases.
extension KeyboardShortcuts.Name {
    // `KeyboardShortcuts.Name` is an immutable value but predates `Sendable`, so Swift 6
    // strict concurrency rejects it as a plain static. It is only ever read, so
    // `nonisolated(unsafe)` is the sanctioned annotation (per the package's Swift 6 guide).
    nonisolated(unsafe) static let summonPalette = Self("summonPalette", default: .init(.space, modifiers: [.option]))
}

/// The curated set of global shortcuts the web settings "Hotkeys" panel can bind the
/// palette to (NIC-76 / FR-UI-06). A fixed set keeps rebinding robust — no fragile
/// web-key→Carbon-keycode translation — while still letting the user change or effectively
/// disable-by-moving the shortcut. The `rawValue` is the id exchanged with the web panel;
/// the preset id is persisted alongside `KeyboardShortcuts`' own storage so the panel can
/// show the current choice.
enum PaletteShortcutPreset: String, CaseIterable {
    case optionSpace = "option-space"
    case commandShiftSpace = "command-shift-space"
    case controlSpace = "control-space"
    case optionCommandK = "option-command-k"

    private static let defaultsKey = "palette.summonPreset"

    /// The persisted current preset (defaults to ⌥Space, matching the `Name` default).
    static var current: PaletteShortcutPreset {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(PaletteShortcutPreset.init(rawValue:)) ?? .optionSpace
    }

    var shortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .optionSpace: return .init(.space, modifiers: [.option])
        case .commandShiftSpace: return .init(.space, modifiers: [.command, .shift])
        case .controlSpace: return .init(.space, modifiers: [.control])
        case .optionCommandK: return .init(.k, modifiers: [.option, .command])
        }
    }

    /// A compact human-readable glyph label (e.g. "⌥Space") for the settings panel.
    var label: String {
        switch self {
        case .optionSpace: return "⌥Space"
        case .commandShiftSpace: return "⌘⇧Space"
        case .controlSpace: return "⌃Space"
        case .optionCommandK: return "⌥⌘K"
        }
    }

    /// Bind the palette summon hotkey to this preset and persist the choice. The existing
    /// `KeyboardShortcuts.onKeyDown(for: .summonPalette)` handler keeps working — the
    /// package re-registers the Carbon hotkey for the new combination.
    func apply() {
        KeyboardShortcuts.setShortcut(shortcut, for: .summonPalette)
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
