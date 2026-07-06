import Foundation

/// Port for per-mode workspace snapshots ("Windows Stored by Mode", NIC-85).
///
/// When the toggle is on, leaving a mode stores the bundle identifiers of the
/// applications that were visible in it; entering the mode returns (un-hides)
/// the still-running ones. Snapshots are operational state in SQLite (ADR-006):
/// bundle-id references only — never paths or executables — and losing one
/// degrades to "nothing to restore", never an error.
public protocol ModeWorkspaceStore: Sendable {
    /// The bundle ids stored for a mode, or `nil` when none were ever stored.
    func loadSnapshot(modeID: String) throws -> [String]?

    /// Replaces the mode's stored snapshot.
    func saveSnapshot(modeID: String, bundleIDs: [String]) throws
}
