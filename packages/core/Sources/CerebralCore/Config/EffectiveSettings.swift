import Foundation
import CerebralContracts

/// Resolves the durable ``StoredSettings`` into the fully-populated
/// ``CerebralHelmSettingsSnapshot`` the settings UI reads on open (NIC-141).
///
/// This is the read side of the write-only settings-patch contract, and the single
/// deterministic place effective defaults live: every consumer reads a resolved
/// value here rather than re-deriving "the default when unset" in its own layer. A
/// stored value always wins; an unset field falls back to its documented default.
///
/// Deliberately narrow: it surfaces only the settings-store-backed fields that have
/// no other delivery channel. Quick apps (bootstrap `modes[].quickApps` +
/// `mode.quickapps.changed`), the login item (`window.__cerebralLoginItem`), the
/// live command-palette hotkey (`window.__cerebralHotkey`), and appearance density
/// (not a live setting for now) are intentionally excluded so no datum has two
/// sources of truth.
public enum EffectiveSettings {
    /// The mode id used when neither a stored default nor a configured default is
    /// available (mirrors ``BootstrapComposer``'s `.executive` fallback so the
    /// settings "Default mode" control and the bootstrap active mode agree on the
    /// floor).
    public static let fallbackModeID = "executive"

    /// The sentinel the shell treats as "host the main dashboard on the system
    /// primary display" (mirrors the dashboard `SYSTEM_PRIMARY` option value). A
    /// stored id that is stale or disconnected also degrades to this at the shell.
    public static let systemPrimaryDisplayID = "system-primary"

    /// The assistant's display name across the dashboard when the user has never
    /// set one — the product's default identity.
    public static let defaultAssistantName = "Heimlich"

    /// The shipped starter ticker list for the Executive Stocks widget (NIC-128),
    /// applied when the user has never configured one. Four symbols — exactly one
    /// 2×2 page — so the widget shows a full grid on first run. A broad-market ETF,
    /// two large caps, and a total-market ETF.
    public static let defaultStockTickers = ["SPY", "AAPL", "NVDA", "VTI"]

    /// The message/document schema version stamped on the snapshot.
    private static let schemaVersion = "1.0.0"

    /// Resolves the snapshot. `configDefaultModeID` is the configured default mode id
    /// (from the layered/shipped config) used when the user has never set one; it is
    /// the "default mode" *setting*, distinct from the currently active mode, so this
    /// never consults last-active-mode state.
    public static func resolve(
        stored: StoredSettings,
        configDefaultModeID: String?
    ) -> CerebralHelmSettingsSnapshot {
        CerebralHelmSettingsSnapshot(
            appearance: SettingsSnapshotAppearance(
                assistantName: stored.appearanceAssistantName ?? defaultAssistantName,
                reducedMotion: stored.appearanceReducedMotion ?? false
            ),
            confirmAllActions: stored.confirmAllActions ?? false,
            defaultModeID: stored.defaultModeID ?? configDefaultModeID ?? fallbackModeID,
            knowledge: SettingsSnapshotKnowledge(
                rootReference: stored.knowledgeRootReference
            ),
            // Sparse pass-through: the client fills palette defaults for any token not
            // overridden. A malformed stored blob degrades to "no overrides" rather than
            // erroring the read.
            modeColors: decodeModeColors(stored.modeColorsJSON),
            schemaVersion: schemaVersion,
            // A stored list wins (including an explicit empty "cleared" list); only a never-set
            // (nil) or malformed blob falls back to the shipped starter list.
            stocks: SettingsSnapshotStocks(
                tickers: decodeStockTickers(stored.stockTickersJSON) ?? defaultStockTickers
            ),
            workspace: SettingsSnapshotWorkspace(
                layoutDisplayID: stored.layoutDisplayID ?? systemPrimaryDisplayID,
                mainDisplayID: stored.mainDisplayID ?? systemPrimaryDisplayID,
                windowsStoredByMode: stored.windowsStoredByMode ?? false
            )
        )
    }

    /// Resolves the effective durable-knowledge root (NIC-138): the user's
    /// `knowledgeRootReference` interpreted as a directory path when set, else the
    /// environment default. An absolute (`/…`) or tilde (`~/…`) reference is used as
    /// given; a bare/relative reference resolves inside the workspace, beside the
    /// default root. Re-point only — the caller never moves or deletes anything at
    /// either location; this only computes where knowledge lives.
    public static func knowledgeRootURL(reference: String?, default defaultRoot: URL) -> URL {
        guard
            let reference,
            !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return defaultRoot
        }
        let expanded = (reference as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = defaultRoot.deletingLastPathComponent().appendingPathComponent(expanded)
        }
        return url.standardizedFileURL
    }

    /// The effective tracked-ticker list for the Stocks widget producer (NIC-128): the stored
    /// list when set (including an explicit empty "cleared" list), else the shipped starter list.
    /// The ``StocksPublisher`` reads this each tick so a Settings edit applies on the next sample.
    public static func resolveStockTickers(stored: StoredSettings) -> [String] {
        decodeStockTickers(stored.stockTickersJSON) ?? defaultStockTickers
    }

    private static func decodeModeColors(_ json: String?) -> [String: String] {
        guard
            let data = json?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    /// Decodes the stored ticker JSON array. Returns `nil` for a never-set (nil) or malformed
    /// blob — the caller then applies the starter default — but returns an explicit `[]` for a
    /// stored empty list, so a user who cleared their tickers keeps an empty widget rather than
    /// having the starter list silently reappear.
    private static func decodeStockTickers(_ json: String?) -> [String]? {
        guard
            let data = json?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        return decoded
    }
}
