import Foundation

/// Session-only, per-mode "collapsed windows" bucket for the bottom-bar
/// collapse/expand-all control (NIC-143).
///
/// Purely in-memory and deliberately NOT persisted: a relaunch starts every mode
/// expanded (owner decision — the bucket does not survive the session). This is
/// distinct from the durable "Windows Stored by Mode" snapshots
/// (``SQLiteModeWorkspaceStore``): that stores a mode's windows across mode
/// switches; this is a transient, on-demand "clear my screen" state a mode can be
/// in, like open vs closed. The two both hide at the application level, so the
/// bridge re-applies this bucket after a mode-switch restore — the collapse bucket
/// is authoritative for its mode.
///
/// A mode is *collapsed* when it holds a bucket: the app bundle ids that were
/// visible when the user pressed collapse (now hidden). Expanding clears it.
/// `@unchecked Sendable`: all access is serialized by the internal lock.
final class ModeCollapseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buckets: [String: [String]] = [:]

    /// True when the mode currently holds a collapsed bucket.
    func isCollapsed(modeID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return buckets[modeID] != nil
    }

    /// The bundle ids collapsed for a mode, or `nil` when the mode is expanded.
    func bucket(modeID: String) -> [String]? {
        lock.lock(); defer { lock.unlock() }
        return buckets[modeID]
    }

    /// Marks a mode collapsed, storing the hidden bundle ids (may be empty).
    func collapse(modeID: String, bundleIDs: [String]) {
        lock.lock(); defer { lock.unlock() }
        buckets[modeID] = bundleIDs
    }

    /// Clears a mode's bucket and returns the bundle ids it held (empty when none).
    @discardableResult
    func expand(modeID: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return buckets.removeValue(forKey: modeID) ?? []
    }
}
