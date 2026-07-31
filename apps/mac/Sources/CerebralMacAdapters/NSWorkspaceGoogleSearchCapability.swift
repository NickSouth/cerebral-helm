// Google-search open (NIC-134) — a reusable "search the web for X" adapter.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Opens a Google search for a query, preferring a running Google Chrome instance (NIC-134).
///
/// The destination is not free-form: the Google search URL is built **host-side** with the host
/// fixed to `www.google.com` and only the query interpolated (via `URLComponents`, which
/// percent-encodes it), so untrusted data — a release title, a note, anything — can never choose
/// the target host. This is the same "constrain, don't accept an arbitrary URL" stance the
/// `project.open` path takes with filesystem paths.
///
/// Destination preference: when Chrome is installed, the URL is opened *with Chrome*
/// (`open(paths:withApplicationAt:)`), which Launch Services routes to the already-running
/// Chrome as a new tab in the current window — an open Chrome instance is the prioritized
/// destination — and otherwise launches Chrome. When Chrome isn't installed, it falls back to
/// the default browser.
public struct NSWorkspaceGoogleSearchCapability: GoogleSearchCapability {
    /// The bundle id of Google Chrome (matches `NSWorkspaceURLCapability`).
    private static let chromeBundleID = "com.google.Chrome"

    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.workspace = workspace
    }

    public func search(query: String) async throws -> GoogleSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.searchURL(query: trimmed) else {
            throw NativeCapabilityError.adapterFailure("Could not build a Google search URL for the query.")
        }
        do {
            if let chromeURL = workspace.installedApplicationURL(forBundleIdentifier: Self.chromeBundleID) {
                // Reuses a running Chrome (new tab) or launches it; never spawns a duplicate.
                try await workspace.open(paths: [url], withApplicationAt: chromeURL)
            } else {
                try await workspace.openURL(url)
            }
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch let error as NativeCapabilityError {
            throw error
        } catch {
            throw NativeCapabilityError.adapterFailure("Opening the Google search failed: \(error.localizedDescription)")
        }
        return GoogleSearchResult(query: trimmed, opened: true, resolvedURL: url.absoluteString)
    }

    // MARK: - Pure helper (unit-tested)

    /// Builds `https://www.google.com/search?q=<query>` with the query percent-encoded. The host
    /// is a literal constant — never derived from the query — so the destination is fixed.
    static func searchURL(query: String) -> URL? {
        guard var components = URLComponents(string: "https://www.google.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}
#endif
