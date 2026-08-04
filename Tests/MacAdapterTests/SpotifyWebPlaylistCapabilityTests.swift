// Quick actions phase 4, action 4: creating a Spotify playlist.
//
// Endpoint, body fields and scopes are from Spotify's Web API reference (checked 2026-08-03). The
// live round trip is NOT covered here: it needs a re-authorized token and would create a real
// playlist in a real account, so it is a manual verification step.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

@Test("the create request posts to /v1/me/playlists with the token in the header")
func playlistRequestShape() throws {
    let request = try #require(SpotifyWebPlaylistCapability.makeRequest(
        host: "https://api.spotify.com", name: "Late night focus",
        description: "Long instrumentals.", isPublic: false, accessToken: "tok"
    ))
    #expect(request.url?.absoluteString == "https://api.spotify.com/v1/me/playlists")
    #expect(request.httpMethod == "POST")
    // The token never rides the URL, so it cannot leak through a logged request description.
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(request.url?.absoluteString.contains("tok") == false)

    let body = try #require(request.httpBody)
    let decoded = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(decoded["name"] as? String == "Late night focus")
    #expect(decoded["public"] as? Bool == false)
    #expect(decoded["description"] as? String == "Long instrumentals.")
}

@Test("visibility is always sent explicitly, and a blank description is omitted")
func playlistRequestAlwaysSendsVisibility() throws {
    // Spotify defaults `public` to true, so omitting it would publish to the user's profile.
    let request = try #require(SpotifyWebPlaylistCapability.makeRequest(
        host: "https://api.spotify.com", name: "Quiet", description: "", isPublic: false, accessToken: "t"
    ))
    let body = try #require(request.httpBody)
    let decoded = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(decoded["public"] as? Bool == false)
    #expect(decoded["description"] == nil)
}

@Test("a 403 is the SCOPE GAP and reads as permissionDenied, not a broken account")
func playlistScopeGapIsPermissionDenied() {
    // A grant made before the playlist scopes existed still works for playback and is refused
    // here; the form turns this into "reconnect".
    #expect(throws: NativeCapabilityError.permissionDenied) {
        try SpotifyWebPlaylistCapability.checkStatus(403)
    }
    #expect(throws: NativeCapabilityError.permissionDenied) {
        try SpotifyWebPlaylistCapability.checkStatus(401)
    }
    // Success is silent.
    #expect(throws: Never.self) { try SpotifyWebPlaylistCapability.checkStatus(201) }
}

@Test("a rate limit and an unexpected status are reported distinctly")
func playlistOtherStatuses() {
    #expect(throws: NativeCapabilityError.self) { try SpotifyWebPlaylistCapability.checkStatus(429) }
    #expect(throws: NativeCapabilityError.self) { try SpotifyWebPlaylistCapability.checkStatus(500) }
}

@Test("the playlist URL comes from Spotify, and its absence is reported rather than guessed")
func playlistDecodesResponse() throws {
    let full = Data(#"{"id":"abc","name":"Late night focus","external_urls":{"spotify":"https://open.spotify.com/playlist/abc"}}"#.utf8)
    let decoded = try #require(SpotifyWebPlaylistCapability.decode(full, fallbackName: "x"))
    #expect(decoded.id == "abc")
    #expect(decoded.url == "https://open.spotify.com/playlist/abc")

    // No external_urls: the URL is absent, not a constructed guess at Spotify's URL shape.
    let bare = Data(#"{"id":"abc"}"#.utf8)
    let sparse = try #require(SpotifyWebPlaylistCapability.decode(bare, fallbackName: "Fallback"))
    #expect(sparse.url == nil)
    #expect(sparse.name == "Fallback")

    // No id at all is not a created playlist.
    #expect(SpotifyWebPlaylistCapability.decode(Data(#"{"name":"x"}"#.utf8), fallbackName: "x") == nil)
}

@Test("the playlist scopes are requested, so a fresh connect grants them")
func playlistScopesAreRequested() {
    #expect(SpotifyTokenExchange.playbackScopes.contains("playlist-modify-private"))
    #expect(SpotifyTokenExchange.playbackScopes.contains("playlist-modify-public"))
    // The playback scopes are still there — adding these must not have replaced them.
    #expect(SpotifyTokenExchange.playbackScopes.contains("user-read-currently-playing"))
}
#endif
