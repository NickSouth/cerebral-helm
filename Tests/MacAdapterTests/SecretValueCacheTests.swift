// Secret value caching (Keychain prompt reduction).
//
// The point of the cache is to spare Keychain *authorization prompts*: every
// publisher re-reads its token each tick, and while the app is ad-hoc signed a
// stale ACL grant turns each of those reads into a password prompt. These tests
// therefore assert the property that produces that benefit — a cached reference
// is served without a Keychain round trip — and the invalidation rules that keep
// a cached value from going stale.
//
// Unlike KeychainSecretCapabilityTests these need no real Keychain and are not
// opt-in: every case below uses a service namespace that holds no items, so a
// read reaching the Keychain would throw `notFound` rather than return a value.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

/// A service namespace guaranteed to hold no Keychain items, so any read that
/// escapes the cache fails loudly instead of returning something plausible.
private func emptyService(_ label: String) -> String {
    "local.cerebralhelm.cachetest.\(ProcessInfo.processInfo.processIdentifier).\(label)"
}

@Test("a cached reference is served without a Keychain round trip")
func cachedReferenceSkipsTheKeychain() async throws {
    let cache = SecretValueCache()
    let service = emptyService("hit")
    let adapter = KeychainSecretCapability(service: service, cache: cache)
    cache.set("cached-token", service: service, reference: "github_api_token")

    // Nothing is stored under this service, so returning the value at all proves
    // the read never reached the Keychain — and therefore never prompted.
    #expect(try await adapter.readValue(reference: "github_api_token") == "cached-token")
}

@Test("an uncached reference still reports notFound honestly")
func uncachedReferenceStillReportsNotFound() async throws {
    let adapter = KeychainSecretCapability(service: emptyService("miss"), cache: SecretValueCache())
    do {
        _ = try await adapter.readValue(reference: "github_api_token")
        Issue.record("Expected notFound for a reference that is neither cached nor stored")
    } catch let error as NativeCapabilityError {
        guard case .notFound = error else {
            Issue.record("Expected .notFound, got \(error)")
            return
        }
    }
}

@Test("copies of the adapter share one cache, so one read spares every publisher's prompt")
func adapterCopiesShareTheCache() async throws {
    // The production adapter is a value type copied into each publisher; the
    // cache must be shared by reference or every copy would prompt separately.
    let cache = SecretValueCache()
    let service = emptyService("shared")
    let first = KeychainSecretCapability(service: service, cache: cache)
    let second = KeychainSecretCapability(service: service, cache: cache)

    cache.set("one-read", service: service, reference: "newsdata_api_key")
    #expect(try await first.readValue(reference: "newsdata_api_key") == "one-read")
    #expect(try await second.readValue(reference: "newsdata_api_key") == "one-read")
}

@Test("delete drops the cached value even when the reference is unbound")
func deleteDropsTheCachedValue() async throws {
    let cache = SecretValueCache()
    let service = emptyService("delete")
    let adapter = KeychainSecretCapability(service: service, cache: cache)
    cache.set("doomed", service: service, reference: "linear_api_token")

    // The Keychain delete fails (nothing is stored) — the cache entry must go
    // anyway, or a failed delete would leave the value readable for the rest of
    // the process's life.
    _ = try? await adapter.delete(reference: "linear_api_token")
    #expect(cache.value(service: service, reference: "linear_api_token") == nil)
}

@Test("deleteAll clears its own service and leaves other namespaces intact")
func deleteAllClearsOnlyItsOwnService() throws {
    let cache = SecretValueCache()
    let mine = emptyService("mine")
    let theirs = emptyService("theirs")
    cache.set("a", service: mine, reference: "tmdb_api_key")
    cache.set("b", service: theirs, reference: "tmdb_api_key")

    try KeychainSecretCapability(service: mine, cache: cache).deleteAll()

    #expect(cache.value(service: mine, reference: "tmdb_api_key") == nil)
    #expect(cache.value(service: theirs, reference: "tmdb_api_key") == "b")
}

@Test("the cache keys on service and reference together, and invalidateAll empties it")
func cacheKeyingAndInvalidation() {
    let cache = SecretValueCache()
    let first = emptyService("keying-first")
    let second = emptyService("keying-second")

    cache.set("first-value", service: first, reference: "shared_name")
    cache.set("second-value", service: second, reference: "shared_name")
    // Same reference name in two namespaces must not collide.
    #expect(cache.value(service: first, reference: "shared_name") == "first-value")
    #expect(cache.value(service: second, reference: "shared_name") == "second-value")

    cache.remove(service: first, reference: "shared_name")
    #expect(cache.value(service: first, reference: "shared_name") == nil)
    #expect(cache.value(service: second, reference: "shared_name") == "second-value")

    cache.invalidateAll()
    #expect(cache.value(service: second, reference: "shared_name") == nil)
}
#endif
