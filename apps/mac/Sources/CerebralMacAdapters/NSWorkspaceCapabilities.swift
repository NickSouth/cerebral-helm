#if canImport(AppKit)
import Foundation
import CerebralTools

/// Opens configured application references through Launch Services (NIC-79,
/// FR-TOL-04/06). Only ids present in the configured reference map can reach the
/// workspace — the tool contract has no path or bundle-id input, so no arbitrary
/// executable path is accepted by construction.
public struct NSWorkspaceAppCapability: AppCapability {
    /// Configured reference id → bundle identifier (`config/references/apps.json`).
    private let apps: [String: String]
    private let workspace: any WorkspaceOpening

    public init(apps: [String: String], workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.apps = apps
        self.workspace = workspace
    }

    public func open(appID: String) async throws -> AppOpenResult {
        guard let bundleID = apps[appID] else {
            throw NativeCapabilityError.notFound(
                "App reference '\(appID)' is not configured. Add it under Settings → Tools before opening it."
            )
        }
        guard let applicationURL = workspace.installedApplicationURL(forBundleIdentifier: bundleID) else {
            throw NativeCapabilityError.notFound(
                "No installed application matches '\(bundleID)' (reference '\(appID)'). Install it or update the reference under Settings → Tools."
            )
        }
        let alreadyRunning = workspace.isApplicationRunning(bundleIdentifier: bundleID)
        do {
            try await workspace.openApplication(at: applicationURL)
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch {
            throw NativeCapabilityError.adapterFailure(
                "Opening '\(appID)' failed: \(error.localizedDescription)"
            )
        }
        return AppOpenResult(appID: appID, launched: !alreadyRunning, alreadyRunning: alreadyRunning)
    }
}

/// Opens configured URL references with the system default handler (NIC-79).
/// Only configured ids resolve; the tool contract carries no raw URL input.
public struct NSWorkspaceURLCapability: URLCapability {
    /// Configured reference id → absolute URL string (`config/references/urls.json`).
    private let urls: [String: String]
    private let workspace: any WorkspaceOpening

    public init(urls: [String: String], workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.urls = urls
        self.workspace = workspace
    }

    public func open(urlID: String) async throws -> URLOpenResult {
        guard let target = urls[urlID] else {
            throw NativeCapabilityError.notFound(
                "URL reference '\(urlID)' is not configured. Add it under Settings → Tools before opening it."
            )
        }
        guard let url = URL(string: target), url.scheme != nil else {
            // A malformed configured target is an adapter-side defect, not a
            // missing reference: config validation should have caught it.
            throw NativeCapabilityError.adapterFailure(
                "The configured target for URL reference '\(urlID)' is not a valid absolute URL."
            )
        }
        do {
            try await workspace.openURL(url)
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch {
            throw NativeCapabilityError.adapterFailure(
                "Opening URL reference '\(urlID)' failed: \(error.localizedDescription)"
            )
        }
        return URLOpenResult(urlID: urlID, opened: true, resolvedURL: target)
    }
}
#endif
