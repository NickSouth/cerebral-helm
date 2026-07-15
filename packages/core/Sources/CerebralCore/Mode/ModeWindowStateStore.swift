import Foundation

/// One window's remembered state within a mode's per-window snapshot — the
/// "each mode is its own laptop" layer (NIC-143 follow-up). Captured when leaving a
/// mode and re-applied when returning, so a window is minimized in the mode you
/// minimized it in and open in the mode you opened it in. Session-only, never persisted.
public struct ModeWindowState: Equatable, Sendable {
    /// The window's opaque id at capture time (the stringified CGWindowID). Stable while
    /// the owning app keeps running; a fallback match by bundle id + title covers the
    /// case where the app was quit and relaunched (a new id).
    public let windowID: String
    public let bundleID: String
    public let title: String
    public let minimized: Bool

    public init(windowID: String, bundleID: String, title: String, minimized: Bool) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.minimized = minimized
    }
}

/// Session-only, per-mode remembered window states. In-memory and never persisted — a
/// relaunch starts with no memory (owner decision). Distinct from the durable, app-level
/// ``ModeWorkspaceStore``: that stores which apps a mode had (and their main-window
/// frames); this stores the per-window open/minimized state on top of it.
public protocol ModeWindowStateStore: Sendable {
    /// The remembered window states for a mode, or `nil` when the mode has never been
    /// captured this session.
    func load(modeID: String) -> [ModeWindowState]?
    /// Replace a mode's remembered window states (captured on leaving that mode).
    func save(modeID: String, windows: [ModeWindowState])
}

/// The default session store: an in-memory map, cleared when the app exits.
/// `@unchecked Sendable`: all access is serialized by the internal lock.
public final class InMemoryModeWindowStateStore: ModeWindowStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byMode: [String: [ModeWindowState]] = [:]

    public init() {}

    public func load(modeID: String) -> [ModeWindowState]? {
        lock.lock(); defer { lock.unlock() }
        return byMode[modeID]
    }

    public func save(modeID: String, windows: [ModeWindowState]) {
        lock.lock(); defer { lock.unlock() }
        byMode[modeID] = windows
    }
}
