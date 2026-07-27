import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-133 Increment 8: the portable `spotify.control` handler validates its I/O against the
/// contract and translates native-capability errors into structured tool errors. The real Web-API
/// PUT/POST is the adapter's job (covered in MacAdapterTests).

@Test("spotify.control echoes the action and reports it applied on success")
func spotifyControlHandlerHappyPath() async throws {
    let handler = SpotifyControlHandler(capability: MockSpotifyControlCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"action":"pause"}"#.utf8))
    let decoded = try CerebralHelmSpotifyControlOutput(data: output)
    #expect(decoded.action == .pause)
    #expect(decoded.applied)
    #expect(decoded.activeDevice)
}

@Test("spotify.control rejects an unknown action as invalidInput before the adapter runs")
func spotifyControlHandlerRejectsUnknownAction() async throws {
    let handler = SpotifyControlHandler(capability: MockSpotifyControlCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"action":"explode"}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("an action outside the contract enum must be rejected as invalid input")
}

@Test("spotify.control with the capability unavailable is a structured unavailable, never a fake success")
func spotifyControlHandlerUnavailable() async throws {
    let handler = SpotifyControlHandler(capability: MockSpotifyControlCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"action":"next"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
