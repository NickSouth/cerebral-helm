import Foundation

/// A window frame in Accessibility (top-left origin) coordinates. Defined in
/// core so workspace snapshots (storage) and window capabilities (tools) share
/// one geometry vocabulary without a dependency between the siblings.
public struct WindowRect: Equatable, Sendable, Codable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One application in a mode's stored workspace: its bundle-id reference and,
/// when the Accessibility capability could read it, its main window's frame.
/// `frame == nil` degrades restore to reactivation-only for that application —
/// honest, never a guess.
public struct WorkspaceAppSnapshot: Equatable, Sendable, Codable {
    public let bundleID: String
    public let frame: WindowRect?

    public init(bundleID: String, frame: WindowRect? = nil) {
        self.bundleID = bundleID
        self.frame = frame
    }
}

/// Port for per-mode workspace snapshots ("Windows Stored by Mode", NIC-85).
///
/// When the toggle is on, leaving a mode stores the applications that were
/// visible in it (with window frames where readable); entering the mode returns
/// (un-hides) the still-running ones and reapplies stored frames where the
/// Accessibility capability allows. Snapshots are operational state in SQLite
/// (ADR-006): bundle-id references only — never paths or executables — and
/// losing one degrades to "nothing to restore", never an error.
public protocol ModeWorkspaceStore: Sendable {
    /// The snapshot stored for a mode, or `nil` when none was ever stored.
    func loadSnapshot(modeID: String) throws -> [WorkspaceAppSnapshot]?

    /// Replaces the mode's stored snapshot.
    func saveSnapshot(modeID: String, apps: [WorkspaceAppSnapshot]) throws
}
