// Native macOS adapters (NIC-79, MAC-ADAPTER-1). This target lives under
// `apps/mac` — the only MVP location that may own native platform adapters
// (repository-boundaries rule 3) — and is compiled empty on non-Apple platforms
// so the package graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation

/// The thin seam over `NSWorkspace` the adapters call through, so reference
/// resolution and error mapping are unit-testable with a fake and the real
/// workspace is touched only by the live app (and manual smoke checks) —
/// contract tests must never launch actual applications.
public protocol WorkspaceOpening: Sendable {
    /// The file URL of the installed application for `bundleID`, or `nil` when
    /// no matching application is installed.
    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL?
    /// Whether an application with `bundleID` is currently running.
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool
    /// Launches (or activates) the application at `url`.
    func openApplication(at url: URL) async throws
    /// Opens `url` with its default handler.
    func openURL(_ url: URL) async throws
}

/// The live `NSWorkspace`-backed implementation the app composes.
public struct SystemWorkspace: WorkspaceOpening {
    public init() {}

    public func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func openApplication(at url: URL) async throws {
        // The completion-handler API is used directly (not the generated async
        // overload) so no non-Sendable NSRunningApplication crosses the
        // concurrency boundary.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func openURL(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
