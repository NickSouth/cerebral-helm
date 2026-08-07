// NIC-82 (MAC-ADAPTER-4): Keychain secret-store adapter.
//
// These tests hit the real login Keychain, isolated under a unique per-run
// service namespace with unconditional cleanup — never fixture values, never a
// shared service (MAC-ADAPTER-4 AC: contract tests use isolated test values).
// On a locked/headless keychain (some CI runners) the probe below bails out
// early rather than failing on environment. Gated so the Linux CI package build
// compiles this target empty.
//
// OPT-IN (CEREBRAL_KEYCHAIN_TESTS=1): the legacy keychain engine (the only one
// an unsigned/ad-hoc process may use — see KeychainSecretCapability) corrupts
// process memory when it runs amid the full suite's parallel allocator load
// (SIGBUS in CSSM, reproduced consistently; isolated runs are stable). Run these
// tests in their own invocation:
//     CEREBRAL_KEYCHAIN_TESTS=1 swift test --filter MacAdapterTests
#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

/// A per-run isolated adapter plus cleanup. The service name embeds the pid and
/// a counter so concurrent suites can never see each other's items.
private let serviceCounter = NSLock()
private nonisolated(unsafe) var serviceSequence = 0
private func isolatedService() -> String {
    serviceCounter.lock()
    serviceSequence += 1
    let sequence = serviceSequence
    serviceCounter.unlock()
    let pid = ProcessInfo.processInfo.processIdentifier
    return "local.cerebralhelm.test.\(pid).\(sequence)"
}

private func isolatedAdapter() -> KeychainSecretCapability {
    KeychainSecretCapability(service: isolatedService())
}

/// `true` when the run opted into real-keychain tests AND the environment has a
/// usable keychain. A locked or unavailable keychain (headless CI) is an
/// environment limitation, not an adapter defect.
private func keychainUsable(_ adapter: KeychainSecretCapability) async -> Bool {
    guard ProcessInfo.processInfo.environment["CEREBRAL_KEYCHAIN_TESTS"] == "1" else { return false }
    do {
        try await adapter.store(reference: "probe", value: "p")
        try await adapter.delete(reference: "probe")
        return true
    } catch NativeCapabilityError.permissionDenied, NativeCapabilityError.unavailable {
        return false
    } catch {
        return true // real defects should surface in the tests, not be skipped
    }
}

@Test("secrets round-trip: create, resolve, read, update, delete (FR-CFG-03)")
func secretRoundTrip() async throws {
    let adapter = isolatedAdapter()
    guard await keychainUsable(adapter) else { return }
    defer { try? adapter.deleteAll() }

    // Unresolved before creation — not an error.
    #expect(try await adapter.resolve(reference: "openai_api_key").isResolved == false)

    try await adapter.store(reference: "openai_api_key", value: "test-value-1")
    let resolution = try await adapter.resolve(reference: "openai_api_key")
    #expect(resolution.isResolved)
    #expect(resolution.reference == "openai_api_key")
    // Invalidated first so the read proves the value was *persisted*, not merely
    // seeded into the write-through cache (SecretValueCacheTests covers the cache).
    SecretValueCache.shared.invalidateAll()
    #expect(try await adapter.readValue(reference: "openai_api_key") == "test-value-1")

    // Update replaces the value in place.
    try await adapter.store(reference: "openai_api_key", value: "test-value-2")
    SecretValueCache.shared.invalidateAll()
    #expect(try await adapter.readValue(reference: "openai_api_key") == "test-value-2")

    try await adapter.delete(reference: "openai_api_key")
    #expect(try await adapter.resolve(reference: "openai_api_key").isResolved == false)
}

@Test("a missing reference is notFound on read and delete, unresolved on resolve")
func missingReferenceSemantics() async throws {
    let adapter = isolatedAdapter()
    guard await keychainUsable(adapter) else { return }
    defer { try? adapter.deleteAll() }

    // resolve: absence is an answer, not an error.
    #expect(try await adapter.resolve(reference: "ghost_key").isResolved == false)

    do {
        _ = try await adapter.readValue(reference: "ghost_key")
        Issue.record("Expected notFound reading a missing secret")
    } catch let error as NativeCapabilityError {
        guard case .notFound = error else { Issue.record("Expected .notFound, got \(error)"); return }
    }
    do {
        try await adapter.delete(reference: "ghost_key")
        Issue.record("Expected notFound deleting a missing secret")
    } catch let error as NativeCapabilityError {
        guard case .notFound = error else { Issue.record("Expected .notFound, got \(error)"); return }
    }
}

@Test("resolution never carries the secret value, and an invalid reference name is rejected")
func resolutionCarriesNoValueAndValidatesNames() async throws {
    let adapter = isolatedAdapter()
    guard await keychainUsable(adapter) else { return }
    defer { try? adapter.deleteAll() }

    try await adapter.store(reference: "db_password", value: "s3cret-value")
    let resolution = try await adapter.resolve(reference: "db_password")
    // The port's shape enforces value-free resolution (reference + flag only);
    // assert the runtime values confirm it.
    #expect(resolution == SecretResolution(reference: "db_password", isResolved: true))

    // Names outside the descriptor schema's logical-reference pattern never
    // reach the keychain.
    do {
        _ = try await adapter.resolve(reference: "Not A Name!")
        Issue.record("Expected an invalid reference to be rejected")
    } catch let error as NativeCapabilityError {
        guard case .adapterFailure = error else { Issue.record("Expected .adapterFailure, got \(error)"); return }
    }
}

@Test("adapters with different service namespaces cannot see each other's secrets")
func serviceNamespacesAreIsolated() async throws {
    let first = isolatedAdapter()
    let second = isolatedAdapter()
    guard await keychainUsable(first) else { return }
    defer {
        try? first.deleteAll()
        try? second.deleteAll()
    }

    try await first.store(reference: "shared_name", value: "first-value")
    #expect(try await first.resolve(reference: "shared_name").isResolved == true)
    #expect(try await second.resolve(reference: "shared_name").isResolved == false)
}

@Test("store is write-through, so a just-stored secret is read back without touching the Keychain")
func storeIsWriteThrough() async throws {
    let service = isolatedService()
    // A cache instance of its own, NOT `SecretValueCache.shared` (flakiness fix, found while
    // running NIC-123's acceptance protocol). This test seeds the cache and then asserts a value
    // still comes back after the Keychain item is deleted — but swift-testing runs tests in
    // parallel, and the round-trip test above calls `SecretValueCache.shared.invalidateAll()` to
    // prove *persistence*. When that landed between this test's store and its read, the cached
    // value vanished and this failed with `.notFound` (reproduced ~1 run in 5, on `main`).
    //
    // The property under test is "a store seeds the cache so the read skips the Keychain", which
    // is about the cache's behaviour, not about that one shared instance — `SecretValueCacheTests`
    // covers `.shared` separately. Using a private instance keeps the assertion identical and
    // makes it independent of what any other test does.
    let adapter = KeychainSecretCapability(service: service, cache: SecretValueCache())
    guard await keychainUsable(adapter) else { return }
    defer { try? adapter.deleteAll() }

    try await adapter.store(reference: "spotify_oauth", value: "token-blob")

    // Remove the underlying item through a *separate* adapter with its own cache:
    // the Keychain item is gone, but the shared cache the first adapter seeded on
    // store is untouched. A value coming back therefore proves the read was served
    // from the cache — the property that spares the authorization prompt.
    let sideDoor = KeychainSecretCapability(service: service, cache: SecretValueCache())
    try await sideDoor.delete(reference: "spotify_oauth")
    #expect(try await adapter.resolve(reference: "spotify_oauth").isResolved == false)
    #expect(try await adapter.readValue(reference: "spotify_oauth") == "token-blob")
}
#endif
