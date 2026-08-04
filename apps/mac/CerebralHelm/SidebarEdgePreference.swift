import Foundation

/// The user's control over the edge-sidebar reveal: whether the left edge is armed at all, and
/// how long the pointer must rest there.
///
/// **Why `UserDefaults` and not the settings contract.** The settings snapshot deliberately omits
/// data that already has its own delivery channel, and names the command-palette hotkey and the
/// login item as exactly that — Mac-only shell behavior, reached over `shellControl` and surfaced
/// to the settings panel through an injected global. The edge reveal is the same kind of thing: a
/// macOS window affordance, not portable durable state, so it follows `PaletteShortcutPreset`
/// rather than adding a required field to a versioned cross-platform contract.
///
/// (If this should instead be portable settings — synced, inspectable in the state root, visible
/// to future non-Mac shells — it belongs in `settings-snapshot.schema.json` with a validator entry.
/// That is a deliberate product call, not a technical constraint.)
enum SidebarEdgePreference {
    private static let enabledKey = "sidebar.edgeRevealEnabled"
    private static let dwellKey = "sidebar.edgeDwellPreset"

    /// Whether a hover-dwell at the left edge reveals the sidebar. On by default — it is the
    /// feature's primary affordance; the hotkey is the alternative, not the baseline.
    static var isEnabled: Bool {
        get {
            // `object(forKey:)` rather than `bool(forKey:)`: the latter returns false for "never
            // set", which would silently ship the feature disabled.
            guard let stored = UserDefaults.standard.object(forKey: enabledKey) as? Bool else {
                return true
            }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The dwell duration, chosen from a fixed set. A closed set (like the hotkey presets) keeps
    /// the stored value trustworthy — no arbitrary number from the web layer can make the edge
    /// either impossible to trigger or so eager that it fires on every pass.
    static var dwell: Dwell {
        get {
            UserDefaults.standard.string(forKey: dwellKey).flatMap(Dwell.init(rawValue:)) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dwellKey) }
    }

    enum Dwell: String, CaseIterable {
        case fast
        case standard
        case relaxed

        var seconds: TimeInterval {
            switch self {
            case .fast: return 0.08
            case .standard: return 0.18
            case .relaxed: return 0.35
            }
        }

        var label: String {
            switch self {
            case .fast: return "Fast"
            case .standard: return "Standard"
            case .relaxed: return "Relaxed"
            }
        }
    }
}
