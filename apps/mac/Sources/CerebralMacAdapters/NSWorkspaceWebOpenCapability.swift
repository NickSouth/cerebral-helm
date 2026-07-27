// Web-address open (NIC-127) — opens a caller-supplied https link (a news article) in the browser.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Opens an https web address, preferring a running Google Chrome instance (NIC-127).
///
/// Unlike ``NSWorkspaceGoogleSearchCapability`` (host-fixed search) or ``NSWorkspaceURLCapability``
/// (configured reference id), the destination here is supplied by the caller — a news headline's
/// article URL, which originates in feed data. It is therefore *validated*, not trusted: the URL
/// must parse, use the `https` scheme, and carry a non-empty host, or it is refused with an honest
/// failure rather than opened. This is the same "constrain, don't accept anything" stance the
/// `project.open` and `google.search` paths take. No credentials or user data are attached — this
/// is plain navigation to a link the user explicitly clicked.
///
/// Destination preference mirrors the Google-search adapter: when Chrome is installed the URL opens
/// *with Chrome* (`open(paths:withApplicationAt:)`), which Launch Services routes to the running
/// Chrome as a new tab; otherwise it falls back to the default browser.
public struct NSWorkspaceWebOpenCapability: WebOpenCapability {
    /// The bundle id of Google Chrome (matches ``NSWorkspaceGoogleSearchCapability``).
    private static let chromeBundleID = "com.google.Chrome"

    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.workspace = workspace
    }

    public func open(url urlString: String) async throws -> WebOpenResult {
        guard let url = Self.validatedURL(urlString) else {
            throw NativeCapabilityError.adapterFailure("Only an absolute https web address can be opened.")
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
            throw NativeCapabilityError.adapterFailure("Opening the web address failed: \(error.localizedDescription)")
        }
        return WebOpenResult(url: url.absoluteString, opened: true)
    }

    // MARK: - Pure helper (unit-tested)

    /// Accepts a URL only when it parses, uses the `https` scheme, and has a non-empty host —
    /// everything else (non-https, scheme-relative, host-less) is rejected so feed data can never
    /// steer the open to a non-web destination.
    static func validatedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
#endif
