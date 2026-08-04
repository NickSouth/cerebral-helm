import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4, action 1: the portable `youtube.search` handler validates its I/O
/// against the contract and translates native-capability errors into structured tool errors. The
/// host-fixed URL construction and Chrome preference are the adapter's job (MacAdapterTests).

@Test("youtube.search echoes the query and reports opened on success")
func youtubeSearchHandlerHappyPath() async throws {
    let handler = YouTubeSearchHandler(capability: MockYouTubeSearchCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"youtubeQuery":"lo-fi study mix"}"#.utf8))
    let decoded = try CerebralHelmYouTubeSearchOutput(data: output)
    #expect(decoded.youtubeQuery == "lo-fi study mix")
    #expect(decoded.youtubeOpened)
    #expect(decoded.youtubeResolvedURL.contains("youtube.com"))
}

@Test("youtube.search rejects malformed input as invalidInput before the adapter runs")
func youtubeSearchHandlerRejectsMalformedInput() async throws {
    let handler = YouTubeSearchHandler(capability: MockYouTubeSearchCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"youtubeQuery":123}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("a non-string query must be rejected as invalid input")
}

@Test("youtube.search with the capability unavailable is a structured unavailable, never a fake success")
func youtubeSearchHandlerUnavailable() async throws {
    let handler = YouTubeSearchHandler(capability: MockYouTubeSearchCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"youtubeQuery":"anything"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
