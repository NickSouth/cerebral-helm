import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// NIC-134 Increment 4: the `storeSecret` / `getSecretStatus` bridge ops provision an API
/// credential into a secret store and report its presence — the value is written but never
/// echoed back (FR-CFG-03, FR-OBS-03). Backed by an in-memory ``MockSecretStore``.

private func secretRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeSecretSession(
    store: (any SecretManaging)?
) throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: secretRepositoryRoot())
    return BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        secretStore: store
    )
}

private func secretPayload(_ json: String) -> [String: JSONAny] {
    (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
}

private func secretRequest(
    _ operation: CerebralContracts.Operation, _ json: String
) -> CerebralHelmBridgeOperationRequest {
    CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_secret01", operation: operation, payload: secretPayload(json),
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

private struct StoreSecretResultDTO: Decodable { let reference: String; let stored: Bool }
private struct SecretStatusResultDTO: Decodable { let reference: String; let bound: Bool }

private func decodeSecret<T: Decodable>(
    _ response: CerebralHelmBridgeOperationResponse, as type: T.Type
) throws -> T {
    let data = try JSONEncoder().encode(response.payload)
    return try JSONDecoder().decode(T.self, from: data)
}

@Test("storeSecret writes the value into the store and reports it bound afterwards")
func storeSecretPersistsAndResolves() async throws {
    let store = MockSecretStore()
    let session = try makeSecretSession(store: store)

    let stored = await session.execute(secretRequest(
        .storeSecret, #"{"reference":"tmdb_api_key","value":"tok_abc123"}"#
    ))
    #expect(stored.status == .ok)
    #expect(try decodeSecret(stored, as: StoreSecretResultDTO.self).stored == true)

    // The value actually landed in the store.
    let value = try await store.readValue(reference: "tmdb_api_key")
    #expect(value == "tok_abc123")

    // And presence now reads bound.
    let status = await session.execute(secretRequest(.getSecretStatus, #"{"reference":"tmdb_api_key"}"#))
    #expect(try decodeSecret(status, as: SecretStatusResultDTO.self).bound == true)
}

@Test("the storeSecret response never echoes the secret value (FR-OBS-03)")
func storeSecretResponseOmitsValue() async throws {
    let session = try makeSecretSession(store: MockSecretStore())
    let response = await session.execute(secretRequest(
        .storeSecret, #"{"reference":"tmdb_api_key","value":"super-secret-value"}"#
    ))
    let json = String(decoding: try JSONEncoder().encode(response.payload), as: UTF8.self)
    #expect(!json.contains("super-secret-value"))
}

@Test("a pasted value is trimmed of surrounding whitespace before storing")
func storeSecretTrimsWhitespace() async throws {
    let store = MockSecretStore()
    let session = try makeSecretSession(store: store)
    _ = await session.execute(secretRequest(
        .storeSecret, #"{"reference":"tmdb_api_key","value":"  tok_trim\n"}"#
    ))
    #expect(try await store.readValue(reference: "tmdb_api_key") == "tok_trim")
}

@Test("storeSecret rejects an empty value rather than storing a blank credential")
func storeSecretRejectsEmptyValue() async throws {
    let store = MockSecretStore()
    let session = try makeSecretSession(store: store)
    let response = await session.execute(secretRequest(
        .storeSecret, #"{"reference":"tmdb_api_key","value":"   "}"#
    ))
    #expect(response.status == .error)
    #expect(response.error?.category == .invalidInput)
    let resolution = try await store.resolve(reference: "tmdb_api_key")
    #expect(resolution.isResolved == false) // nothing was stored
}

@Test("getSecretStatus reports an unbound reference as not set")
func secretStatusUnboundIsNotSet() async throws {
    let session = try makeSecretSession(store: MockSecretStore())
    let status = await session.execute(secretRequest(.getSecretStatus, #"{"reference":"tmdb_api_key"}"#))
    #expect(status.status == .ok)
    #expect(try decodeSecret(status, as: SecretStatusResultDTO.self).bound == false)
}

@Test("storeSecret without a secret store degrades honestly, never a fabricated success")
func storeSecretWithoutStoreIsUnavailable() async throws {
    let session = try makeSecretSession(store: nil)
    let response = await session.execute(secretRequest(
        .storeSecret, #"{"reference":"tmdb_api_key","value":"tok"}"#
    ))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
}
