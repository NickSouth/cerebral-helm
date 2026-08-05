import Foundation

/// Composes several ``NewsProvider``s into one, trying them in order until a provider yields
/// headlines (the news quota fix, increment 2).
///
/// The News panel is backed by a metered provider (NewsData's free tier is ~200 requests/day), and
/// a widget that goes blank when a quota runs out is worse than one backed by a slightly plainer
/// source. Ordering the chain `[metered, free]` means the panel keeps working through a rate limit,
/// an outage, or an unconfigured API key, which is the "missing integrations degrade gracefully
/// rather than disabling the surface" rule applied to a widget.
///
/// A provider that returns **no** headlines is treated the same as one that failed — an empty list
/// is not a usable answer for the panel, so the chain moves on rather than rendering an empty
/// region while a working source sits unused behind it.
///
/// When every provider fails the **first** error is rethrown, not the last: the first provider is
/// the one the user configured, so its diagnosis is the actionable one. That is what keeps the
/// honest "add your NewsData API key" guidance reaching the panel when the key is missing *and*
/// the free fallback is also unreachable — while a working fallback quietly takes over when it is
/// not, so a user with no key still sees news.
public struct FallbackNewsProvider: NewsProvider {
    private let providers: [any NewsProvider]

    public init(_ providers: [any NewsProvider]) {
        self.providers = providers
    }

    public func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
        var firstError: Error?
        for provider in providers {
            do {
                let headlines = try await provider.headlines(profile: profile, apiToken: apiToken)
                if !headlines.isEmpty { return headlines }
                if firstError == nil {
                    firstError = NewsError.providerFailed("The news provider returned no headlines.")
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? NewsError.providerFailed("No news provider is configured.")
    }
}
