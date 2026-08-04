// The system-health inventory (quick actions phase 5) — what `system-status-checks` runs.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore
import CerebralTools

/// Composes the live health checks for this Mac.
///
/// **The selection rule, from the owner (2026-08-04): everything that can change without a code
/// change, and nothing that cannot.** The test suite already proves the code is self-consistent —
/// it has to pass for a build to exist — so re-running any of it here would report a guarantee
/// rather than a finding. What no test can tell you is whether the world still matches: a
/// permission revoked in System Settings, a token that expired overnight, an undocumented endpoint
/// whose fields moved, a folder renamed in Finder. Every row below is one of those.
///
/// Two invariants hold across the whole inventory:
///
/// - **Nothing here writes.** Every check is a read, so running them can never be the thing that
///   breaks something.
/// - **Nothing here spends a quota.** Providers with a small free budget are verified only as far
///   as is free, and the row says so in words rather than implying a probe that never happened.
///   NewsData's 200/day has already been exhausted once by an over-eager caller; a daily health
///   check that consumed it would be a self-inflicted outage.
public enum SystemHealthChecks {
    /// Everything the Mac host can check.
    ///
    /// `session` is injected so the network checks share the app's ephemeral configuration and can
    /// be faked in tests; `now` is injected because freshness is a comparison against a clock, and
    /// a check that read the wall clock directly could not be tested.
    public static func all(
        permissions: any PermissionChecking,
        secrets: any SecretStoreManaging,
        knowledgeRoot: String,
        projectsRoot: String,
        databasePath: String,
        canvasStatus: (@Sendable () async -> CanvasHealthSnapshot)? = nil,
        session: URLSession = SystemHealthChecks.defaultSession(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> [any HealthCheck] {
        permissionChecks(permissions)
            + surfaceChecks()
            + integrationChecks(secrets: secrets, session: session)
            + storageChecks(
                knowledgeRoot: knowledgeRoot, projectsRoot: projectsRoot, databasePath: databasePath
            )
            + (canvasStatus.map { [canvasCheck(status: $0, now: now)] } ?? [])
    }

    /// A short-lived session: these are one-off probes, and a cached 200 from an hour ago would
    /// make a dead endpoint look alive — the exact failure the checks exist to catch.
    public static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    // MARK: - Permissions

    /// The macOS grants. Every one of these can flip in System Settings while the app is running,
    /// and the first two flip **on every rebuild** because the Debug app is ad-hoc signed.
    static func permissionChecks(_ permissions: any PermissionChecking) -> [any HealthCheck] {
        [
            PermissionHealthCheck(
                id: "permission.accessibility",
                title: "Accessibility",
                permissionID: "accessibility",
                checker: permissions,
                detail: "Window arranging, layouts, and the window navigator.",
                remediation: "System Settings → Privacy & Security → Accessibility. After a rebuild, remove CerebralHelm and add it again."
            ),
            PermissionHealthCheck(
                id: "permission.contacts",
                title: "Contacts",
                permissionID: "contacts_read",
                checker: permissions,
                detail: "Who `send-text` can send to.",
                remediation: "System Settings → Privacy & Security → Contacts."
            ),
            PermissionHealthCheck(
                id: "permission.location",
                title: "Location",
                permissionID: "location",
                checker: permissions,
                detail: "The weather reading in the bottom bar.",
                remediation: "System Settings → Privacy & Security → Location Services."
            )
        ]
    }

    // MARK: - macOS surfaces

    /// Applications and URL handlers the app hands work to.
    ///
    /// These are the quietest failures in the whole app: nothing errors when Obsidian is missing,
    /// the note simply never opens. A check is the only way any of it surfaces.
    static func surfaceChecks() -> [any HealthCheck] {
        [
            InlineHealthCheck(
                id: "surface.obsidian",
                title: "Obsidian",
                group: .permissions,
                detail: "Opening a note from `search-notes` and `take-notes`."
            ) {
                guard let probe = URL(string: "obsidian://open"),
                      NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
                else {
                    return .failed(
                        reason: "Nothing on this Mac handles obsidian:// links.",
                        remediation: "Install Obsidian. Notes still reveal in Finder without it."
                    )
                }
                // The limitation worth stating every time: the URI scheme cannot register a vault,
                // and nothing can detect whether yours is registered. A silent no-op looks
                // identical to success from here, so the row says so rather than claiming more.
                return .passed(
                    detail: "Installed. Your knowledge folder must be added as a vault once — that can't be detected from here."
                )
            },
            InlineHealthCheck(
                id: "surface.chrome",
                title: "Google Chrome",
                group: .permissions,
                detail: "Per-mode windows and profile-specific quick apps."
            ) {
                guard NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.google.Chrome"
                ) != nil else {
                    return .skipped(reason: "Not installed — links open in your default browser.")
                }
                return .passed(detail: "Installed.")
            },
            InlineHealthCheck(
                id: "surface.messages",
                title: "Messages",
                group: .permissions,
                detail: "Sending a text from `send-text`."
            ) {
                guard NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.MobileSMS"
                ) != nil else {
                    return .failed(reason: "Messages is not available on this Mac.", remediation: nil)
                }
                // Automation is granted on first send and cannot be read without triggering it —
                // so this stops at "the app is there" rather than pretending to know more.
                return .passed(
                    detail: "Installed. Automation access is granted the first time you send."
                )
            }
        ]
    }

    // MARK: - Integrations

    /// Third-party services: the credential, and where it is free to do so, the live contract.
    static func integrationChecks(
        secrets: any SecretStoreManaging, session: URLSession
    ) -> [any HealthCheck] {
        [
            SecretHealthCheck(
                id: "integration.linear",
                title: "Linear",
                reference: "linear_api_token",
                secrets: secrets,
                detail: "`create-ticket`, and the team/project/label dropdowns.",
                unboundReason: "No API key — `create-ticket` is unavailable.",
                remediation: "Settings → Setup → Linear API key.",
                probe: { token in await LinearProbe.run(token: token, session: session) }
            ),
            SecretHealthCheck(
                id: "integration.github",
                title: "GitHub",
                reference: "github_api_token",
                secrets: secrets,
                detail: "The Developer repo-status widget.",
                unboundReason: "No token — the repo widget shows local branch state only.",
                remediation: "Settings → Setup → GitHub token.",
                // `/rate_limit` is the one endpoint that does not itself count against the limit,
                // so this verifies the token AND reports the budget without spending any of it.
                probe: { token in await GitHubProbe.run(token: token, session: session) }
            ),
            SecretHealthCheck(
                id: "integration.spotify",
                title: "Spotify",
                reference: "spotify_oauth",
                secrets: secrets,
                detail: "Now playing, playback controls, and `create-playlist`.",
                unboundReason: "Not connected.",
                remediation: "Settings → Setup → Connect Spotify."
            ),
            SecretHealthCheck(
                id: "integration.tmdb",
                title: "TMDB",
                reference: "tmdb_api_key",
                secrets: secrets,
                detail: "The Releases widget and `suggest-a-movie`.",
                unboundReason: "No API key — the Releases widget is empty.",
                remediation: "Settings → Setup → TMDB API key."
            ),
            SecretHealthCheck(
                id: "integration.finnhub",
                title: "Finnhub",
                reference: "finnhub_api_key",
                secrets: secrets,
                detail: "The Executive stocks widget.",
                unboundReason: "No API key — the stocks widget is empty.",
                remediation: "Settings → Setup → Finnhub API key."
            ),
            SecretHealthCheck(
                id: "integration.newsdata",
                title: "NewsData",
                reference: "newsdata_api_key",
                secrets: secrets,
                detail: "The News panel.",
                unboundReason: "No API key — the News panel is empty.",
                remediation: "Settings → Setup → NewsData API key."
                // No probe, deliberately: 200 requests a day, already exhausted once by an
                // over-eager caller. A daily health check that spent one would be absurd.
            ),
            EndpointHealthCheck(
                id: "integration.espn",
                title: "ESPN scoreboard",
                url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!,
                session: session,
                detail: "`check-scoreboard`. Undocumented — this is the one that can move.",
                remediation: "Nothing to fix locally: the mapper degrades rather than throwing, so scores go missing rather than the action breaking.",
                validate: ESPNProbe.validate
            ),
            EndpointHealthCheck(
                id: "integration.openmeteo",
                title: "Open-Meteo",
                url: URL(string: "https://api.open-meteo.com/v1/forecast?latitude=42.39&longitude=-72.52&current=temperature_2m")!,
                session: session,
                detail: "The weather reading. No key, no quota.",
                validate: OpenMeteoProbe.validate
            )
        ]
    }

    // MARK: - Storage

    /// The local state everything durable depends on. Renaming a folder in Finder is the cheapest
    /// way to break the app from outside the code, and nothing notices until a write fails.
    static func storageChecks(
        knowledgeRoot: String, projectsRoot: String, databasePath: String
    ) -> [any HealthCheck] {
        [
            PathHealthCheck(
                id: "storage.knowledge",
                title: "Knowledge root",
                path: knowledgeRoot,
                requiresWrite: true,
                detail: "Where every note is captured and read.",
                remediation: "Settings → Setup → Knowledge folder."
            ),
            PathHealthCheck(
                id: "storage.projects",
                title: "Projects root",
                path: projectsRoot,
                requiresWrite: true,
                detail: "Where `git-clone` and `create-project` write."
            ),
            InlineHealthCheck(
                id: "storage.database",
                title: "Operational database",
                group: .storage,
                detail: "Settings, mode state, widget caches."
            ) {
                guard FileManager.default.fileExists(atPath: databasePath) else {
                    // Absent is not broken: the database is created on first write, so a fresh
                    // install legitimately has none yet.
                    return .skipped(reason: "Not created yet — it appears on first write.")
                }
                guard FileManager.default.isWritableFile(atPath: databasePath) else {
                    return .failed(reason: "Not writable.", remediation: nil)
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: databasePath)[.size]) as? Int ?? 0
                return .passed(detail: "\(size / 1024) KB.")
            }
        ]
    }

    /// Canvas is scraped by a browser extension, so it stops silently: the extension is disabled,
    /// or the user has not opened the dashboard in a fortnight, and the widgets quietly serve
    /// stale data. Freshness is the only signal there is.
    static func canvasCheck(
        status: @escaping @Sendable () async -> CanvasHealthSnapshot,
        now: @escaping @Sendable () -> Date
    ) -> any HealthCheck {
        InlineHealthCheck(
            id: "integration.canvas",
            title: "Canvas",
            group: .integrations,
            detail: "The School deadlines and course widgets."
        ) {
            let snapshot = await status()
            guard snapshot.paired else {
                return .skipped(reason: "Extension not paired — the School widgets are empty.")
            }
            guard let scraped = snapshot.lastScrapedAt else {
                return .failed(
                    reason: "Paired, but nothing has been scraped yet.",
                    remediation: "Open your Canvas dashboard in Chrome once."
                )
            }
            let age = now().timeIntervalSince(scraped)
            let days = Int(age / 86_400)
            if age > 7 * 86_400 {
                return .failed(
                    reason: "Last scraped \(days) days ago — the widgets are showing stale data.",
                    remediation: "Open your Canvas dashboard in Chrome."
                )
            }
            return .passed(
                detail: days == 0 ? "Scraped today." : "Scraped \(days) day\(days == 1 ? "" : "s") ago."
            )
        }
    }
}

/// What the health check needs to know about Canvas, without depending on the bridge's own status
/// type — the check asks two questions and this carries exactly those two answers.
public struct CanvasHealthSnapshot: Sendable, Equatable {
    public let paired: Bool
    public let lastScrapedAt: Date?

    public init(paired: Bool, lastScrapedAt: Date?) {
        self.paired = paired
        self.lastScrapedAt = lastScrapedAt
    }
}
#endif
