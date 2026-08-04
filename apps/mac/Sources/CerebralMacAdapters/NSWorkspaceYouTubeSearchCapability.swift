// YouTube-search open (quick-actions phase 4) — the `search-youtube` quick action's actuator.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Opens a YouTube search for a query, preferring a running Google Chrome instance.
///
/// A near-copy of ``NSWorkspaceGoogleSearchCapability`` on purpose. The destination is not
/// free-form: the results URL is built **host-side** with the host fixed to `www.youtube.com` and
/// only the query interpolated (via `URLComponents`, which percent-encodes it), so untrusted data
/// can never choose the target host. A shared adapter taking the host as a parameter would hand
/// that choice back to the caller, which is precisely what this construction exists to prevent —
/// so the duplication is the point, not an oversight.
///
/// Destination preference matches the Google adapter: when Chrome is installed the URL is opened
/// *with Chrome* (`open(paths:withApplicationAt:)`), which Launch Services routes to an
/// already-running Chrome as a new tab; otherwise it falls back to the default browser.
public struct NSWorkspaceYouTubeSearchCapability: YouTubeSearchCapability {
    /// The bundle id of Google Chrome (matches ``NSWorkspaceGoogleSearchCapability``).
    private static let chromeBundleID = "com.google.Chrome"

    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.workspace = workspace
    }

    public func search(query: String) async throws -> YouTubeSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = Self.searchURL(query: trimmed) else {
            throw NativeCapabilityError.adapterFailure("Could not build a YouTube search URL for the query.")
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
            throw NativeCapabilityError.adapterFailure("Opening the YouTube search failed: \(error.localizedDescription)")
        }
        return YouTubeSearchResult(query: trimmed, opened: true, resolvedURL: url.absoluteString)
    }

    // MARK: - Pure helper (unit-tested)

    /// Builds `https://www.youtube.com/results?search_query=<query>` with the query percent-encoded.
    /// The host is a literal constant — never derived from the query — so the destination is fixed.
    static func searchURL(query: String) -> URL? {
        guard var components = URLComponents(string: "https://www.youtube.com/results") else { return nil }
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url
    }
}
#endif
