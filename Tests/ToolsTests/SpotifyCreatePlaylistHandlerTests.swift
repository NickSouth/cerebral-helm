import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4, action 4: the portable `spotify.createplaylist` handler validates its I/O
/// and translates native-capability errors. The OAuth session, the scope gap and the HTTP round
/// trip are the adapter's job.

@Test("spotify.createplaylist returns the id and name Spotify assigned")
func spotifyCreatePlaylistHappyPath() async throws {
    let handler = SpotifyCreatePlaylistHandler(capability: MockSpotifyPlaylistCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"playlistName":"Late night focus"}"#.utf8))
    let decoded = try CerebralHelmSpotifyCreatePlaylistOutput(data: output)
    #expect(decoded.playlistName == "Late night focus")
    #expect(!decoded.playlistID.isEmpty)
}

@Test("an omitted visibility means PRIVATE, not Spotify's public default")
func spotifyCreatePlaylistDefaultsPrivate() async throws {
    // Spotify's API defaults `public` to true. Inheriting that would publish to someone's profile
    // because a field was left out, so the handler decides rather than passing the absence along.
    let recorder = RecordingPlaylistCapability()
    let handler = SpotifyCreatePlaylistHandler(capability: recorder)
    _ = try await handler.execute(input: Data(#"{"playlistName":"Quiet"}"#.utf8))
    #expect(recorder.lastIsPublic == false)

    _ = try await handler.execute(input: Data(#"{"playlistName":"Loud","playlistIsPublic":true}"#.utf8))
    #expect(recorder.lastIsPublic == true)
}

@Test("spotify.createplaylist rejects a nameless playlist before the adapter runs")
func spotifyCreatePlaylistRequiresName() async throws {
    let handler = SpotifyCreatePlaylistHandler(capability: MockSpotifyPlaylistCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"playlistIsPublic":false}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("input with no name must be rejected as invalid input")
}

@Test("spotify.createplaylist with the capability unavailable never reports a fake success")
func spotifyCreatePlaylistUnavailable() async throws {
    let handler = SpotifyCreatePlaylistHandler(capability: MockSpotifyPlaylistCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"playlistName":"x"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}

/// Records what the handler passed through, so the visibility default is checked at the boundary
/// it is actually decided at. Mutations run through a non-async helper (Swift 6 lock rules).
private final class RecordingPlaylistCapability: SpotifyPlaylistCapability, @unchecked Sendable {
    private let lock = NSLock()
    private var isPublic: Bool?

    func createPlaylist(name: String, description: String?, isPublic: Bool) async throws -> SpotifyPlaylistResult {
        record(isPublic)
        return SpotifyPlaylistResult(id: "p1", name: name, url: nil)
    }

    private func record(_ value: Bool) { lock.lock(); isPublic = value; lock.unlock() }

    var lastIsPublic: Bool? { lock.lock(); defer { lock.unlock() }; return isPublic }
}
