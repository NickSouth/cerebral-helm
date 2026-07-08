#if canImport(AppKit)
import AppKit
import CerebralTools

/// The seam over the running-application surface, so the adapter's selection and
/// best-effort semantics are testable with a fake (same pattern as
/// ``WorkspaceOpening``).
public protocol RunningApplicationSource: Sendable {
    /// Snapshot of running applications: bundle id, whether it is a regular
    /// (Dock-visible) app, and whether it is currently hidden.
    func runningApplications() -> [RunningApplicationInfo]
    /// Hide the application; returns whether the request was accepted.
    func hide(bundleID: String) -> Bool
    /// Un-hide the application; returns whether the request was accepted.
    func unhide(bundleID: String) -> Bool
    /// The host app's own bundle id (never hidden or stored).
    var ownBundleID: String? { get }
}

public struct RunningApplicationInfo: Equatable, Sendable {
    public let bundleID: String
    public let isRegular: Bool
    public let isHidden: Bool

    public init(bundleID: String, isRegular: Bool, isHidden: Bool) {
        self.bundleID = bundleID
        self.isRegular = isRegular
        self.isHidden = isHidden
    }
}

/// Live `NSWorkspace`/`NSRunningApplication` source. Permission-free public API:
/// hide/unhide whole applications, no Accessibility involvement.
public struct SystemRunningApplications: RunningApplicationSource {
    public init() {}

    public var ownBundleID: String? { Bundle.main.bundleIdentifier }

    public func runningApplications() -> [RunningApplicationInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return RunningApplicationInfo(
                bundleID: bundleID,
                isRegular: app.activationPolicy == .regular,
                isHidden: app.isHidden
            )
        }
    }

    public func hide(bundleID: String) -> Bool {
        applications(bundleID).map { $0.hide() }.contains(true)
    }

    public func unhide(bundleID: String) -> Bool {
        applications(bundleID).map { $0.unhide() }.contains(true)
    }

    private func applications(_ bundleID: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
}

/// Native ``WorkspaceWindowsCapability`` ("Windows Stored by Mode", NIC-85):
/// application-level hide and return via `NSRunningApplication`. Best-effort by
/// contract — results report the bundle ids actually affected; ids that are not
/// running are simply absent, and the host app itself is never touched.
public struct MacWorkspaceWindowsCapability: WorkspaceWindowsCapability {
    private let source: any RunningApplicationSource

    public init(source: any RunningApplicationSource = SystemRunningApplications()) {
        self.source = source
    }

    public func visibleApplicationBundleIDs() async throws -> [String] {
        source.runningApplications()
            .filter { $0.isRegular && !$0.isHidden && $0.bundleID != source.ownBundleID }
            .map(\.bundleID)
    }

    public func hideApplications(bundleIDs: [String]) async throws -> [String] {
        bundleIDs.filter { $0 != source.ownBundleID && source.hide(bundleID: $0) }
    }

    public func unhideApplications(bundleIDs: [String]) async throws -> [String] {
        bundleIDs.filter { $0 != source.ownBundleID && source.unhide(bundleID: $0) }
    }
}
#endif
