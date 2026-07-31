import Foundation

/// Whether a release is a film or an episodic series (NIC-134). Provider-neutral — a concrete
/// provider maps its own vocabulary (TMDB's `media_type`, Increment 3) onto these cases, and
/// the event mapping encodes the `rawValue` so the dashboard's `ReleaseWidgetItem.mediaType`
/// (`"movie" | "tv"`) matches by construction.
public enum ReleaseMediaType: String, Equatable, Sendable {
    case movie
    case tv
}

/// A single new/hot release for the Entertainment "Releases" widget (NIC-134). Produced by a
/// ``ReleaseProvider`` and mapped to the widget envelope by the live producer (Increment 5).
/// `year` is optional because a provider may have no release date for an item — it is omitted,
/// never fabricated.
public struct ReleaseItem: Equatable, Sendable {
    /// Stable provider id (TMDB id as a string), used as the dashboard row key.
    public let id: String
    /// Display title (a movie `title` or a series `name`).
    public let title: String
    /// Film vs series.
    public let mediaType: ReleaseMediaType
    /// Release/first-air year, or nil when the provider has no date.
    public let year: Int?
    /// The poster artwork as a self-contained `data:` URI (base64), or nil when the provider had
    /// no poster or it couldn't be fetched — the card then falls back to a title-only placeholder,
    /// never a broken image. Embedded as a data URI (like app/URL icons) because the dashboard's
    /// `cerebral://` origin does not load external image URLs; the adapter fetches it natively.
    public let posterImage: String?

    public init(id: String, title: String, mediaType: ReleaseMediaType, year: Int?, posterImage: String? = nil) {
        self.id = id
        self.title = title
        self.mediaType = mediaType
        self.year = year
        self.posterImage = posterImage
    }
}

/// Why a releases fetch could not be produced. Kept coarse and provider-neutral: the event
/// mapping degrades any failure to an honest `unavailable` widget, distinguishing only a
/// missing credential (so the widget can say "add your API key") from a provider/network
/// failure. FR-CFG-03/FR-SAF-07: a missing secret becomes honest guidance, never a fabricated
/// list. ``credentialsMissing`` is thrown by the publisher when the Keychain reference is
/// unbound (Increment 5) — the provider itself only ever reports ``providerFailed``.
public enum ReleaseError: Error, Equatable, Sendable {
    /// No API credential is configured — the widget should guide the user to add one.
    case credentialsMissing
    /// The release provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that fetches the current new/hot releases (NIC-134). Provider-neutral and
/// credential-driven: the caller (the ``ReleasesPublisher``, Increment 5) resolves the API
/// token from the Keychain and passes it in, so this contract never touches the secret store.
/// Async because a real provider performs a network fetch (TMDB, Increment 3); the mock
/// resolves synchronously. Throws ``ReleaseError`` on failure — the mapping treats it as an
/// honest `unavailable`, never a made-up list.
public protocol ReleaseProvider: Sendable {
    func trending(apiToken: String) async throws -> [ReleaseItem]
}

/// A fixed-outcome ``ReleaseProvider`` for pre-Mac builds and tests: it ignores the token and
/// always yields the items (or throws the error) it was constructed with.
public struct MockReleaseProvider: ReleaseProvider {
    private let outcome: Result<[ReleaseItem], ReleaseError>

    public init(items: [ReleaseItem]) {
        self.outcome = .success(items)
    }

    public init(error: ReleaseError) {
        self.outcome = .failure(error)
    }

    public func trending(apiToken: String) async throws -> [ReleaseItem] {
        try outcome.get()
    }
}
