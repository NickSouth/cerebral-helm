#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Opens configured application references through Launch Services (NIC-79,
/// FR-TOL-04/06). Only ids present in the configured reference map can reach the
/// workspace — the tool contract has no path or bundle-id input, so no arbitrary
/// executable path is accepted by construction.
public struct NSWorkspaceAppCapability: AppCapability {
    /// Configured reference id → resolved reference (`config/references/apps.json`),
    /// resolved on each call so a mid-session mint is picked up live (NIC-146). The
    /// full entry is carried (not just its bundle-id target) so the optional Chrome
    /// `profile` (NIC-151) is visible to the open path.
    private let appsProvider: @Sendable () -> [String: ReferenceEntry]
    private let workspace: any WorkspaceOpening
    /// Chrome's bundle id — a profile on a reference targeting Chrome routes through
    /// the profile-window launcher so it focuses (not reopens) the profile's window.
    private static let chromeBundleID = "com.google.Chrome"
    /// Focuses/reuses a Chrome profile's window (NIC-151). `nil` falls back to a plain
    /// `--profile-directory` launch (a new window each time).
    private let chromeLauncher: ChromeProfileLauncher?

    /// Static map (tests, and any host with a fixed catalog). The values are bare
    /// bundle-id targets, so every entry is profile-less — the plain launch path.
    public init(apps: [String: String], workspace: any WorkspaceOpening = SystemWorkspace()) {
        let entries = Dictionary(uniqueKeysWithValues: apps.map { key, bundleID in
            (key, ReferenceEntry(id: key, label: key, target: bundleID))
        })
        self.init(appsProvider: { entries }, workspace: workspace)
    }

    /// Live map backed by the shared reference store (NIC-146), so `open <id>` resolves
    /// a reference minted after startup without a relaunch. `chromeLauncher` routes a
    /// Chrome-targeted profile reference to the profile-window registry (NIC-151).
    public init(
        appsProvider: @escaping @Sendable () -> [String: ReferenceEntry],
        workspace: any WorkspaceOpening = SystemWorkspace(),
        chromeLauncher: ChromeProfileLauncher? = nil
    ) {
        self.appsProvider = appsProvider
        self.workspace = workspace
        self.chromeLauncher = chromeLauncher
    }

    public func open(appID: String) async throws -> AppOpenResult {
        guard let entry = appsProvider()[appID] else {
            throw NativeCapabilityError.notFound(
                "App reference '\(appID)' is not configured. Add it under Settings → Tools before opening it."
            )
        }
        let bundleID = entry.target
        guard let applicationURL = workspace.installedApplicationURL(forBundleIdentifier: bundleID) else {
            throw NativeCapabilityError.notFound(
                "No installed application matches '\(bundleID)' (reference '\(appID)'). Install it or update the reference under Settings → Tools."
            )
        }
        let alreadyRunning = workspace.isApplicationRunning(bundleIdentifier: bundleID)

        // A Chrome-targeted profile reference (a pinned "Chrome — <profile>") routes
        // through the launcher, which focuses the profile's existing window instead of
        // reopening one every launch (NIC-151, Nick's window registry). Bare Chrome:
        // no URL, so the launcher just focuses (or opens) the profile window.
        if let profile = entry.profile, bundleID == Self.chromeBundleID, let chromeLauncher {
            do {
                let outcome = try await chromeLauncher.open(profile: profile, url: nil)
                return AppOpenResult(
                    appID: appID, launched: outcome == .launched, alreadyRunning: outcome != .launched
                )
            } catch is CancellationError {
                throw NativeCapabilityError.cancelled
            } catch let error as NativeCapabilityError {
                throw error
            } catch {
                throw NativeCapabilityError.adapterFailure("Opening '\(appID)' failed: \(error.localizedDescription)")
            }
        }

        do {
            // A profile-bearing reference launches the app with the Chrome
            // `--profile-directory` flag (NIC-151). The app is explicit here (the
            // reference names it), so — unlike the URL path — there is no
            // force-Chrome branch: Chromium-family apps honor the flag, others
            // ignore it, which is the user's configuration choice.
            if let profile = entry.profile {
                try await workspace.openApplication(at: applicationURL, arguments: ["--profile-directory=\(profile)"])
            } else {
                try await workspace.openApplication(at: applicationURL)
            }
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
    /// The bundle id of Google Chrome — the only browser whose per-profile launch
    /// flag (`--profile-directory`) CH honors (NIC-151). A profile-bearing URL
    /// reference opens in Chrome specifically, not the default browser.
    private static let chromeBundleID = "com.google.Chrome"

    /// Configured reference id → resolved reference (`config/references/urls.json` +
    /// user-minted URLs), resolved on each call so a URL added mid-session opens live
    /// without a relaunch (NIC-146). The full entry is carried (not just its target)
    /// so the optional Chrome `profile` (NIC-151) is visible to the open path.
    private let urlsProvider: @Sendable () -> [String: ReferenceEntry]
    private let workspace: any WorkspaceOpening
    /// Focuses an existing browser tab CH opened for this URL (NIC-145), or `nil`
    /// on hosts without surfacing (tests, pre-Mac).
    private let surface: (any BrowserTabSurface)?
    /// Records which `(modeID, urlID)` pairs CH opened this session, so surfacing is
    /// only attempted for a URL CH itself opened in the current mode. `nil` disables it.
    private let registry: SessionURLOpenRegistry?
    /// The active mode at open time (`ModeStateStore.loadActiveModeID()`), or `nil`
    /// when no mode is active — in which case surfacing is skipped and nothing is
    /// recorded (there is no mode to scope the record to).
    private let currentModeProvider: @Sendable () -> String?
    /// Opens a profile-bearing URL in its Chrome profile window, reusing an existing
    /// window when one is live (NIC-151). `nil` falls back to a direct profile launch.
    private let chromeLauncher: ChromeProfileLauncher?

    /// Static map (tests, and any host with a fixed catalog). The values are bare
    /// target strings, so every entry is profile-less — the plain open path.
    public init(urls: [String: String], workspace: any WorkspaceOpening = SystemWorkspace()) {
        let entries = Dictionary(uniqueKeysWithValues: urls.map { key, target in
            (key, ReferenceEntry(id: key, label: key, target: target))
        })
        self.init(urlsProvider: { entries }, workspace: workspace)
    }

    /// Live map backed by the shared reference store (NIC-146): a URL minted through
    /// `addUrlReference` resolves the same session. `surface`/`registry`/
    /// `currentModeProvider` opt this adapter into re-open surfacing (NIC-145);
    /// omitting them preserves the plain open-a-new-tab behavior. `chromeLauncher`
    /// routes profiled URLs to the profile-window registry (NIC-151).
    public init(
        urlsProvider: @escaping @Sendable () -> [String: ReferenceEntry],
        workspace: any WorkspaceOpening = SystemWorkspace(),
        surface: (any BrowserTabSurface)? = nil,
        registry: SessionURLOpenRegistry? = nil,
        currentModeProvider: @escaping @Sendable () -> String? = { nil },
        chromeLauncher: ChromeProfileLauncher? = nil
    ) {
        self.urlsProvider = urlsProvider
        self.workspace = workspace
        self.surface = surface
        self.registry = registry
        self.currentModeProvider = currentModeProvider
        self.chromeLauncher = chromeLauncher
    }

    public func open(urlID: String) async throws -> URLOpenResult {
        guard let entry = urlsProvider()[urlID] else {
            throw NativeCapabilityError.notFound(
                "URL reference '\(urlID)' is not configured. Add it under Settings → Tools before opening it."
            )
        }
        let target = entry.target
        guard let url = URL(string: target), url.scheme != nil else {
            // A malformed configured target is an adapter-side defect, not a
            // missing reference: config validation should have caught it.
            throw NativeCapabilityError.adapterFailure(
                "The configured target for URL reference '\(urlID)' is not a valid absolute URL."
            )
        }

        // A profile-bearing reference opens in its Chrome profile (NIC-151). The
        // launcher does PROFILE-SCOPED surfacing: it focuses a matching tab only in
        // the profile's own window, or opens/launches there — it never surfaces a tab
        // in a different profile (Nick's requirement). This deliberately does NOT use
        // the profile-blind NIC-145 global surfacer below.
        if let profile = entry.profile {
            do {
                if let chromeLauncher {
                    let outcome = try await chromeLauncher.open(profile: profile, url: url)
                    return URLOpenResult(
                        urlID: urlID, opened: outcome != .surfacedExistingTab, resolvedURL: target,
                        surfaced: outcome == .surfacedExistingTab
                    )
                }
                // Fallback (no launcher wired): a direct profile launch with the URL as
                // a command-line ARGUMENT so Chrome routes it into the profile — never
                // as an open-document, which a running Chrome opens in the current
                // profile (the bug NIC-151 fixes).
                guard let chromeURL = workspace.installedApplicationURL(forBundleIdentifier: Self.chromeBundleID) else {
                    throw NativeCapabilityError.notFound(
                        "Google Chrome isn't installed, so URL reference '\(urlID)' can't open in the '\(profile)' profile. Install Chrome, or remove the profile from the reference."
                    )
                }
                try await workspace.openApplication(
                    at: chromeURL, arguments: ["--profile-directory=\(profile)", url.absoluteString]
                )
                return URLOpenResult(urlID: urlID, opened: true, resolvedURL: target, surfaced: false)
            } catch is CancellationError {
                throw NativeCapabilityError.cancelled
            } catch let error as NativeCapabilityError {
                throw error
            } catch {
                throw NativeCapabilityError.adapterFailure(
                    "Opening URL reference '\(urlID)' in Chrome profile '\(profile)' failed: \(error.localizedDescription)"
                )
            }
        }

        let modeID = currentModeProvider()

        // Plain (profile-less) URL: NIC-145 profile-blind surfacing — re-opening in the
        // same mode focuses the existing tab on the domain (any route/subdomain) rather
        // than duplicating it. Only for a URL CH itself opened in this mode; any
        // non-`surfaced` outcome falls through to a fresh open.
        if let modeID, let surface, let registry, registry.contains(modeID: modeID, urlID: urlID) {
            if case .surfaced = await surface.surface(url: url) {
                return URLOpenResult(urlID: urlID, opened: false, resolvedURL: target, surfaced: true)
            }
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
        // Remember that CH opened this URL in this mode, so the next trigger can
        // surface it rather than duplicate it.
        if let modeID { registry?.record(modeID: modeID, urlID: urlID) }
        return URLOpenResult(urlID: urlID, opened: true, resolvedURL: target, surfaced: false)
    }
}
#endif
