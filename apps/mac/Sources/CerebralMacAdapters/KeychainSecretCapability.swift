// Keychain secret-store adapter (NIC-82, MAC-ADAPTER-4, FR-CFG-03).
#if canImport(AppKit)
import Foundation
import Security
import CerebralTools

/// Resolves and manages logical secret references through the login Keychain
/// (ADR-008: unsandboxed app, generic-password items, no access-group scoping).
///
/// Shape:
/// - One Keychain **generic password** item per reference: the service is a
///   stable namespace (`local.cerebralhelm.secrets`), the account is the logical
///   reference name, the data is the secret value.
/// - ``SecretCapability/resolve(reference:)`` — the only surface tools and
///   config resolution see — answers *presence only*; the value never crosses
///   that port (FR-CFG-03: config carries references, never values).
/// - ``SecretStoreManaging`` is the provisioning surface (settings flow, contract
///   tests). Its `readValue` returns the live secret; callers must never log or
///   persist it.
/// - `readValue` is served from a process-lifetime ``SecretValueCache`` so a
///   secret costs at most one authorization prompt per launch instead of one per
///   publisher tick. `resolve` deliberately stays uncached: it reads attributes
///   only (`kSecReturnAttributes`, never `kSecReturnData`), so it performs no
///   decrypt and never prompts — caching it would trade honest presence for
///   nothing.
///
/// Error semantics (MAC-ADAPTER-4): a missing reference is `notFound` (or an
/// unresolved resolution — not an error); a locked or denied keychain is
/// `permissionDenied`; an unavailable keychain daemon is `unavailable`; anything
/// else surfaces as `adapterFailure` with the OSStatus in the diagnostic. A
/// secret failure affects only secret operations — no other capability consults
/// the keychain, so unrelated tools are untouched by construction.

public struct KeychainSecretCapability: SecretManaging {
    /// All SecItem calls are serialized process-wide, and this adapter uses the
    /// *legacy* keychain engine deliberately: the modern data-protection keychain
    /// (`kSecUseDataProtectionKeychain`, which bypasses the fragile CSSM engine)
    /// requires a real signing identity — ad-hoc dev builds get
    /// `errSecMissingEntitlement`, and forged entitlements are AMFI-killed
    /// (verified 2026-07-05). Switch to the data-protection keychain when
    /// MAC-UPDATE-2 brings Developer ID signing. Until then the lock removes the
    /// engine's intra-process race (observed as SIGBUS under heavy test
    /// concurrency: `Security::DbModifier::commit` racing
    /// `SecItemCopyMatching_osx`); secret operations are rare and millisecond-
    /// scale, so serialization costs nothing.
    private static let keychainLock = NSLock()

    private let service: String
    private let cache: SecretValueCache

    /// `cache` defaults to the process-wide store so every copy of this value
    /// type shares one set of grants; tests pass a private instance for isolation.
    public init(
        service: String = "local.cerebralhelm.secrets",
        cache: SecretValueCache = .shared
    ) {
        self.service = service
        self.cache = cache
    }

    // MARK: - SecretCapability (presence only; the tool-facing port)

    public func resolve(reference: String) async throws -> SecretResolution {
        try Self.validate(reference)
        var query = baseQuery(reference)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = Self.withKeychainLock { SecItemCopyMatching(query as CFDictionary, &result) }
        switch status {
        case errSecSuccess:
            return SecretResolution(reference: reference, isResolved: true)
        case errSecItemNotFound:
            return SecretResolution(reference: reference, isResolved: false)
        default:
            throw Self.capabilityError(status, reference: reference)
        }
    }

    // MARK: - SecretStoreManaging (provisioning surface)

    public func store(reference: String, value: String) async throws {
        try Self.validate(reference)
        let data = Data(value.utf8)
        var attributes = baseQuery(reference)
        attributes[kSecValueData as String] = data

        let status = Self.withKeychainLock {
            var status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecDuplicateItem {
                // Update-in-place keeps the item's identity (and any future ACL) stable.
                status = SecItemUpdate(
                    baseQuery(reference) as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary
                )
            }
            return status
        }
        guard status == errSecSuccess else {
            throw Self.capabilityError(status, reference: reference)
        }
        // Write-through: the value we just persisted is authoritative, so a
        // reader on the next tick needs neither a Keychain round trip nor the
        // authorization prompt that would come with it.
        cache.set(value, service: service, reference: reference)
    }

    public func readValue(reference: String) async throws -> String {
        try Self.validate(reference)
        if let cached = cache.value(service: service, reference: reference) {
            return cached
        }
        var query = baseQuery(reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = Self.withKeychainLock { SecItemCopyMatching(query as CFDictionary, &result) }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Self.capabilityError(status, reference: reference)
        }
        let value = String(decoding: data, as: UTF8.self)
        cache.set(value, service: service, reference: reference)
        return value
    }

    public func delete(reference: String) async throws {
        try Self.validate(reference)
        let status = Self.withKeychainLock { SecItemDelete(baseQuery(reference) as CFDictionary) }
        // Dropped unconditionally: on success the value is gone, and on failure a
        // stale cache entry would be worse than the extra read the miss costs.
        cache.remove(service: service, reference: reference)
        guard status == errSecSuccess else {
            throw Self.capabilityError(status, reference: reference)
        }
    }

    /// Removes every secret under this adapter's service namespace. Exists for
    /// test isolation and a future explicit "reset secrets" recovery path — it is
    /// deliberately not part of ``SecretStoreManaging``.
    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = Self.withKeychainLock { SecItemDelete(query as CFDictionary) }
        cache.removeAll(service: service)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.capabilityError(status, reference: "*")
        }
    }

    // MARK: - Internals

    private static func withKeychainLock<T>(_ body: () -> T) -> T {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        return body()
    }

    private func baseQuery(_ reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
        ]
    }

    /// Logical reference names follow the descriptor schema's pattern
    /// (`^[a-z][a-z0-9_]*$`) so config, descriptors, and keychain accounts agree.
    private static func validate(_ reference: String) throws {
        let lowercase = "abcdefghijklmnopqrstuvwxyz"
        let valid = reference.first.map(lowercase.contains) == true
            && reference.allSatisfy { lowercase.contains($0) || $0.isNumber || $0 == "_" }
        guard valid else {
            throw NativeCapabilityError.adapterFailure(
                "Secret reference '\(reference)' is not a valid logical name (expected lowercase letters, digits, and underscores)."
            )
        }
    }

    private static func capabilityError(_ status: OSStatus, reference: String) -> NativeCapabilityError {
        switch status {
        case errSecItemNotFound:
            return .notFound("No secret is stored for reference '\(reference)'.")
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecInteractionRequired:
            return .permissionDenied
        case errSecNotAvailable:
            return .unavailable
        default:
            return .adapterFailure("Keychain operation for '\(reference)' failed (OSStatus \(status)).")
        }
    }
}

/// Process-lifetime cache of secret *values*, keyed by `(service, reference)`.
///
/// Exists to cut Keychain **authorization prompts**, not I/O. Every publisher
/// re-reads its token each tick (Spotify every 3–12 s, stocks/mail every 5 min,
/// git status every 10 min, releases every 30 min, news every 2 h), and each
/// read of a distinct item is a separate ACL evaluation. While the app is
/// ad-hoc signed its ACL grants are pinned to the binary's `cdhash` and are
/// orphaned by every rebuild, so an un-cached read storm turns one stale grant
/// into a prompt per item that keeps re-firing on the next tick. Caching makes
/// that at most one prompt per item per launch.
///
/// The cache is **write-through, never time-based**: ``KeychainSecretCapability/store(reference:value:)``
/// seeds it and ``KeychainSecretCapability/delete(reference:)`` drops the entry,
/// so the settings flow's "a newly entered key takes effect on the next tick"
/// contract still holds without a Keychain round trip. Only successful reads are
/// cached — a `notFound` never prompts, so caching absence would buy nothing and
/// would mask a reference bound out-of-band.
///
/// Accepted trade-off: a secret edited **externally** (Keychain Access, the
/// `security` CLI) while the app is running is not seen until relaunch. Every
/// in-app write path goes through `store`, so this only affects manual edits.
///
/// A `final class` rather than an `actor` because ``KeychainSecretCapability/deleteAll()``
/// is synchronous; the lock matches the adapter's existing `keychainLock` idiom.
public final class SecretValueCache: @unchecked Sendable {
    /// The process-wide default. Instances of the adapter are value types copied
    /// into each publisher, so the cache must be shared by reference for a read
    /// on one copy to spare a prompt on another.
    public static let shared = SecretValueCache()

    private let lock = NSLock()
    private var values: [Key: String] = [:]

    private struct Key: Hashable {
        let service: String
        let reference: String
    }

    public init() {}

    func value(service: String, reference: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[Key(service: service, reference: reference)]
    }

    func set(_ value: String, service: String, reference: String) {
        lock.lock()
        defer { lock.unlock() }
        values[Key(service: service, reference: reference)] = value
    }

    func remove(service: String, reference: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: Key(service: service, reference: reference))
    }

    func removeAll(service: String) {
        lock.lock()
        defer { lock.unlock() }
        values = values.filter { $0.key.service != service }
    }

    /// Drops every cached value. The recovery affordance for an out-of-band edit,
    /// and how tests force a read to reach the real Keychain.
    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}
#endif
