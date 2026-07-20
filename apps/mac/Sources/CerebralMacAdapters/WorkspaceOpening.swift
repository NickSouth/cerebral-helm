// Native macOS adapters (NIC-79, MAC-ADAPTER-1). This target lives under
// `apps/mac` — the only MVP location that may own native platform adapters
// (repository-boundaries rule 3) — and is compiled empty on non-Apple platforms
// so the package graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

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
    /// Launches the application at `url`, passing `arguments` on launch. Used to
    /// open an app reference in a specific Chrome profile (`--profile-directory`,
    /// NIC-151); a fresh instance is launched so the arguments reach the app.
    func openApplication(at url: URL, arguments: [String]) async throws
    /// Opens `url` with its default handler.
    func openURL(_ url: URL) async throws
    /// Opens the given file-system paths (e.g. a repository directory) with the
    /// application at `applicationURL` — Launch Services asks that app to open them
    /// (NIC-131). Used to open a repo folder in the configured editor; unlike
    /// `openApplication(at:arguments:)`, the app decides how to handle the documents,
    /// so an editor reuses its running instance instead of spawning a new one.
    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws
    /// The bundle id of the default web browser (the app that handles `https`), or
    /// `nil` when it can't be resolved. Lets the URL adapter route a plain URL into a
    /// per-mode Chrome window only when Chrome is actually the default (NIC-143 follow-up).
    func defaultBrowserBundleID() -> String?
}

public extension WorkspaceOpening {
    /// Default: unknown default browser — a fake without a browser degrades to the plain
    /// open path.
    func defaultBrowserBundleID() -> String? { nil }

    /// Default: a conformer that does not open documents reports the capability as
    /// unavailable (fails closed) — so a fake that never overrides this can't silently
    /// succeed. The live ``SystemWorkspace`` overrides it.
    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {
        throw NativeCapabilityError.unavailable
    }
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

    public func defaultBrowserBundleID() -> String? {
        guard let https = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: https) else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
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

    public func openApplication(at url: URL, arguments: [String]) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        // A fresh instance so the launch arguments (the `--profile-directory` flag)
        // reach the app: a running Chrome forwards this instance's command line to
        // its singleton and opens the named profile, then the new instance exits.
        configuration.createsNewApplicationInstance = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
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

    public func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {
        // "Open these documents with this application" — Launch Services hands the paths
        // to the app, which (for an editor like VS Code) opens the folder in its running
        // instance. A plain application launch with the paths as arguments would instead
        // spawn a new instance, so this uses the document-open API deliberately.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.open(
                paths, withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
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
