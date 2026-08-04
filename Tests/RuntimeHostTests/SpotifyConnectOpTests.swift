import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// NIC-133 Increment 6: the `connectSpotify` op runs the injected OAuth connect flow and reports
/// success + scope (never the tokens), degrading honestly on failure; the generic `deleteSecret` op
/// backs the disconnect. Backed by an in-memory ``MockSecretStore``.

private func spotifyOpRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeSpotifyOpSession(
    store: (any SecretManaging)? = nil,
    spotifyConnect: (@Sendable () async throws -> SpotifyConnectionInfo)? = nil,
    onSecretDeleted: (@Sendable (String) -> Void)? = nil
) throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: spotifyOpRepositoryRoot())
    return BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        secretStore: store,
        onSecretDeleted: onSecretDeleted,
        spotifyConnect: spotifyConnect
    )
}

/// Records the references a bridge session reported as deleted.
private final class DeletedReferenceLog: @unchecked Sendable {
    private let lock = NSLock()
    private var references: [String] = []

    func record(_ reference: String) {
        lock.lock(); defer { lock.unlock() }
        references.append(reference)
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }
        return references
    }
}

private func spotifyOpRequest(
    _ operation: CerebralContracts.Operation, _ json: String = "{}"
) -> CerebralHelmBridgeOperationRequest {
    let payload = (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
    return CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_spotifyop01", operation: operation, payload: payload,
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

private func decodeSpotifyOp<T: Decodable>(
    _ response: CerebralHelmBridgeOperationResponse, as type: T.Type
) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(response.payload))
}

private struct ConnectResultDTO: Decodable { let connected: Bool; let scope: String? }
private struct DeleteResultDTO: Decodable { let reference: String; let deleted: Bool }

@Test("connectSpotify reports connected + the granted scope, never the tokens")
func spotifyConnectSucceeds() async throws {
    let session = try makeSpotifyOpSession(store: MockSecretStore(), spotifyConnect: {
        SpotifyConnectionInfo(scope: "user-read-currently-playing user-modify-playback-state")
    })
    let response = await session.execute(spotifyOpRequest(.connectSpotify))
    #expect(response.status == .ok)
    let result = try decodeSpotifyOp(response, as: ConnectResultDTO.self)
    #expect(result.connected == true)
    #expect(result.scope == "user-read-currently-playing user-modify-playback-state")
    // No token field could ever be present — the payload carries only connected + scope.
    let json = String(decoding: try JSONEncoder().encode(response.payload), as: UTF8.self)
    #expect(!json.lowercased().contains("token"))
}

@Test("connectSpotify with no Client ID guides the user to add one")
func spotifyConnectMissingClientID() async throws {
    let session = try makeSpotifyOpSession(spotifyConnect: {
        throw SpotifyPlaybackError.credentialsMissing
    })
    let response = await session.execute(spotifyOpRequest(.connectSpotify))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
    #expect(response.error?.message.contains("Client ID") == true)
}

@Test("a connect failure degrades to a generic retry message, never leaking a diagnostic")
func spotifyConnectFailureIsGeneric() async throws {
    let session = try makeSpotifyOpSession(spotifyConnect: {
        throw SpotifyPlaybackError.providerFailed("timeout at 127.0.0.1:8888")
    })
    let response = await session.execute(spotifyOpRequest(.connectSpotify))
    #expect(response.status == .error)
    #expect(response.error?.message.contains("127.0.0.1") == false)
    #expect(response.error?.message.contains("Couldn't connect") == true)
}

@Test("connectSpotify without the Mac coordinator degrades honestly as unavailable")
func spotifyConnectUnavailableWithoutHost() async throws {
    let session = try makeSpotifyOpSession(spotifyConnect: nil)
    let response = await session.execute(spotifyOpRequest(.connectSpotify))
    #expect(response.status == .error)
    #expect(response.error?.category == .unavailableCapability)
}

@Test("deleteSecret removes a stored secret, and status then reads not-set")
func spotifyDeleteSecretRemoves() async throws {
    let store = MockSecretStore(values: ["spotify_oauth": "{\"blob\":true}"])
    let session = try makeSpotifyOpSession(store: store)

    let response = await session.execute(spotifyOpRequest(.deleteSecret, #"{"reference":"spotify_oauth"}"#))
    #expect(response.status == .ok)
    #expect(try decodeSpotifyOp(response, as: DeleteResultDTO.self).deleted == true)
    #expect(try await store.resolve(reference: "spotify_oauth").isResolved == false)
}

@Test("deleteSecret notifies the host, so a session holding the grant in memory can drop it")
func spotifyDeleteSecretNotifiesTheHost() async throws {
    // The OAuth sessions cache their token rather than re-reading the Keychain on every tick, so a
    // Disconnect that only removed the stored item would be cosmetic — the session would keep using
    // the revoked credential. This hook is what makes the disconnect real.
    let log = DeletedReferenceLog()
    let store = MockSecretStore(values: ["spotify_oauth": "{\"blob\":true}"])
    let session = try makeSpotifyOpSession(store: store, onSecretDeleted: { log.record($0) })

    let response = await session.execute(spotifyOpRequest(.deleteSecret, #"{"reference":"spotify_oauth"}"#))
    #expect(response.status == .ok)
    #expect(log.recorded == ["spotify_oauth"])
}

@Test("deleteSecret does not notify the host when there was nothing to delete")
func spotifyDeleteSecretDoesNotNotifyOnNoOp() async throws {
    let log = DeletedReferenceLog()
    let session = try makeSpotifyOpSession(store: MockSecretStore(), onSecretDeleted: { log.record($0) })

    let response = await session.execute(spotifyOpRequest(.deleteSecret, #"{"reference":"spotify_oauth"}"#))
    #expect(response.status == .ok)
    // No grant existed, so no consumer can be holding one — a spurious invalidate would drop a
    // perfectly good token from an unrelated session.
    #expect(log.recorded.isEmpty)
}

@Test("deleteSecret on an already-absent reference is an idempotent no-op success")
func spotifyDeleteSecretIdempotent() async throws {
    let session = try makeSpotifyOpSession(store: MockSecretStore())
    let response = await session.execute(spotifyOpRequest(.deleteSecret, #"{"reference":"spotify_oauth"}"#))
    #expect(response.status == .ok)
    #expect(try decodeSpotifyOp(response, as: DeleteResultDTO.self).deleted == false)
}
