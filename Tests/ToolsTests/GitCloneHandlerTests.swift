import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4, action 2: the portable `git.clone` handler validates its I/O against the
/// contract and translates native-capability errors into structured tool errors. URL validation,
/// projects-root containment, and the actual process are the adapter's job (MacAdapterTests).

@Test("git.clone returns the path it cloned to")
func gitCloneHandlerHappyPath() async throws {
    let handler = GitCloneHandler(capability: MockGitCloneCapability(matrix: .allAvailable))
    let input = #"{"repositoryURL":"https://example.com/owner/repo.git","cloneDirectory":"repo"}"#
    let output = try await handler.execute(input: Data(input.utf8))
    let decoded = try CerebralHelmGitCloneOutput(data: output)
    #expect(decoded.clonedRepositoryName == "repo")
    #expect(decoded.clonedPath.hasSuffix("/repo"))
}

@Test("git.clone accepts an omitted folder — the adapter derives one")
func gitCloneHandlerAllowsNoDirectory() async throws {
    let handler = GitCloneHandler(capability: MockGitCloneCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"repositoryURL":"https://example.com/o/r"}"#.utf8))
    #expect(try CerebralHelmGitCloneOutput(data: output).clonedRepositoryName.isEmpty == false)
}

@Test("git.clone rejects malformed input as invalidInput before the adapter runs")
func gitCloneHandlerRejectsMalformedInput() async throws {
    let handler = GitCloneHandler(capability: MockGitCloneCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"cloneDirectory":"repo"}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("input with no repository URL must be rejected as invalid input")
}

@Test("git.clone with the capability unavailable is a structured unavailable, never a fake success")
func gitCloneHandlerUnavailable() async throws {
    let handler = GitCloneHandler(capability: MockGitCloneCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"repositoryURL":"https://example.com/o/r"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
