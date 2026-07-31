// NIC-133 Increment 8: the Spotify playback-control request building + response interpretation.
// The live PUT/POST is smoked once a real authorization exists (Nick's machine).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralTools
@testable import CerebralMacAdapters

@Test("each action maps to the right endpoint + method, with the token in the header not the URL")
func spotifyControlRequests() throws {
    let cases: [(String, String, String)] = [
        ("play", "/v1/me/player/play", "PUT"),
        ("pause", "/v1/me/player/pause", "PUT"),
        ("next", "/v1/me/player/next", "POST"),
        ("previous", "/v1/me/player/previous", "POST"),
    ]
    for (action, path, method) in cases {
        let request = try #require(SpotifyWebControlCapability.makeRequest(
            host: "https://api.spotify.com", action: action, accessToken: "secret-token"
        ))
        #expect(request.url?.absoluteString == "https://api.spotify.com\(path)")
        #expect(request.httpMethod == method)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(!(request.url?.absoluteString.contains("secret-token") ?? true))
    }
    // An action outside the set has no request (the contract enum rejects it upstream anyway).
    #expect(SpotifyWebControlCapability.makeRequest(host: "https://api.spotify.com", action: "explode", accessToken: "t") == nil)
}

@Test("a 2xx is applied; a 404 is an honest no-active-device; 401/403 deny; else unavailable")
func spotifyControlInterpret() throws {
    // 204 (and any 2xx) → applied on an active device.
    let ok = try SpotifyWebControlCapability.interpret(action: "pause", statusCode: 204)
    #expect(ok.applied)
    #expect(ok.activeDevice)

    // 404 NO_ACTIVE_DEVICE → honest "nothing to control", never an error.
    let noDevice = try SpotifyWebControlCapability.interpret(action: "pause", statusCode: 404)
    #expect(!noDevice.applied)
    #expect(!noDevice.activeDevice)

    // 401 (token rejected) / 403 (Premium required) → denied.
    #expect(throws: NativeCapabilityError.self) {
        _ = try SpotifyWebControlCapability.interpret(action: "play", statusCode: 401)
    }
    #expect(throws: NativeCapabilityError.self) {
        _ = try SpotifyWebControlCapability.interpret(action: "play", statusCode: 403)
    }
    // Anything else → unavailable.
    #expect(throws: NativeCapabilityError.self) {
        _ = try SpotifyWebControlCapability.interpret(action: "play", statusCode: 500)
    }
}
#endif
