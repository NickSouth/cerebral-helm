import Foundation

/// A single headline for the bottom-left News panel (NIC-127). Produced by a ``NewsProvider``
/// and mapped to the `DashboardNewsRegion` by the event mapping (this increment) / the live
/// producer (Increment 7). `url` is the headline's navigable destination (design spec §5.4) —
/// optional because a source may occasionally lack a link, in which case it is omitted (never
/// fabricated) and the panel renders the headline as non-interactive text.
public struct NewsHeadline: Equatable, Sendable {
    /// Stable per-item id, used as the dashboard row key.
    public let id: String
    /// The headline text.
    public let title: String
    /// The publication/source name (e.g. "Reuters").
    public let source: String
    /// The article URL to open on click, or nil when the source has no link.
    public let url: String?

    public init(id: String, title: String, source: String, url: String? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.url = url
    }
}

/// Why a news fetch could not be produced. Kept coarse and provider-neutral: the event mapping
/// degrades any failure to an honest `unavailable` region, distinguishing only a missing
/// credential (so the panel can guide the user to add their key) from a provider/network
/// failure. FR-CFG-03/FR-SAF-07: a missing secret becomes honest guidance, never a fabricated
/// list. ``credentialsMissing`` is thrown by the publisher when the Keychain reference is
/// unbound (Increment 7) — the provider itself only ever reports ``providerFailed``.
public enum NewsError: Error, Equatable, Sendable {
    /// No API credential is configured — the panel should guide the user to add one.
    case credentialsMissing
    /// The news provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that fetches the current headlines for one relevance profile (NIC-127). Provider-neutral,
/// profile-driven, and credential-driven: the caller (the ``NewsPublisher``, Increment 7) passes
/// the active mode's `newsProfile` and resolves the API token from the Keychain, so this contract
/// never touches the secret store and never hardcodes a source — a concrete provider maps the
/// profile to its own query/category (via config, Increment 5). Async because a real provider
/// performs a network fetch; the mock resolves synchronously. Throws ``NewsError`` on failure —
/// the mapping treats it as an honest `unavailable`, never a made-up list.
public protocol NewsProvider: Sendable {
    func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline]
}

/// A fixed-outcome ``NewsProvider`` for pre-Mac builds and tests: it ignores the profile and
/// token and always yields the headlines (or throws the error) it was constructed with.
public struct MockNewsProvider: NewsProvider {
    private let outcome: Result<[NewsHeadline], NewsError>

    public init(headlines: [NewsHeadline]) {
        self.outcome = .success(headlines)
    }

    public init(error: NewsError) {
        self.outcome = .failure(error)
    }

    public func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
        try outcome.get()
    }
}
