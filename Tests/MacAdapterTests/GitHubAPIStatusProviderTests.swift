// NIC-130: GitHub REST request building, response parsing, CI collapse, and rate-limit detection.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the request targets the GitHub API with the token in the Authorization header, not the URL")
func gitHubAPIRequestCarriesTokenInHeader() throws {
    let request = try #require(GitHubAPIStatusProvider.makeRequest(
        host: "https://api.github.com",
        path: "/repos/NickSouth/cerebral-helm/pulls",
        queryItems: [.init(name: "state", value: "open")],
        apiToken: "ghp_secret_token"
    ))
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "api.github.com")
    #expect(components.path == "/repos/NickSouth/cerebral-helm/pulls")
    #expect(components.queryItems?.first(where: { $0.name == "state" })?.value == "open")

    // The token rides the header — never the URL, so it can't leak into logs.
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_secret_token")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    #expect(!url.absoluteString.contains("ghp_secret_token"))
}

@Test("open PRs parse to a count and the first non-blank titles")
func gitHubAPIParsesPullRequests() throws {
    let json = Data("""
    [
      { "number": 7, "title": "Repo status widget" },
      { "number": 6, "title": "  " },
      { "number": 5, "title": "Weather integration" }
    ]
    """.utf8)
    let prs = try GitHubAPIStatusProvider.parsePullRequests(json)
    #expect(prs.count == 3) // every open PR object is counted
    #expect(prs.titles == ["Repo status widget", "Weather integration"]) // blank title dropped
}

@Test("commits parse to a first-line message and a short SHA")
func gitHubAPIParsesCommits() throws {
    let json = Data("""
    [
      { "sha": "320ac4c1234567", "commit": { "message": "fix: news formatting\\n\\nlonger body" } },
      { "sha": "c1a4f7edeadbeef", "commit": { "message": "feat: news widget" } }
    ]
    """.utf8)
    let commits = try GitHubAPIStatusProvider.parseCommits(json)
    #expect(commits.count == 2)
    #expect(commits.first?.shortSha == "320ac4c") // first 7 chars
    #expect(commits.first?.message == "fix: news formatting") // subject only, body dropped
}

@Test("no Actions runs on a branch collapse to none — a repo without CI reads as complete")
func gitHubAPIChecksNoRuns() throws {
    let json = Data(#"{ "total_count": 0, "workflow_runs": [] }"#.utf8)
    #expect(try GitHubAPIStatusProvider.checksState(fromActionsRuns: json) == GitHubChecksState.none)
}

@Test("the latest Actions run collapses to passing / failing / pending by status and conclusion")
func gitHubAPIChecksCollapse() throws {
    let success = Data(#"{ "workflow_runs": [{ "status": "completed", "conclusion": "success" }] }"#.utf8)
    #expect(try GitHubAPIStatusProvider.checksState(fromActionsRuns: success) == .passing)

    let failure = Data(#"{ "workflow_runs": [{ "status": "completed", "conclusion": "failure" }] }"#.utf8)
    #expect(try GitHubAPIStatusProvider.checksState(fromActionsRuns: failure) == .failing)

    let running = Data(#"{ "workflow_runs": [{ "status": "in_progress", "conclusion": null }] }"#.utf8)
    #expect(try GitHubAPIStatusProvider.checksState(fromActionsRuns: running) == .pending)

    // An inconclusive completed run (cancelled) is not claimed as pass or fail → none.
    let cancelled = Data(#"{ "workflow_runs": [{ "status": "completed", "conclusion": "cancelled" }] }"#.utf8)
    #expect(try GitHubAPIStatusProvider.checksState(fromActionsRuns: cancelled) == GitHubChecksState.none)
}

@Test("the repository response parses its default branch")
func gitHubAPIParsesDefaultBranch() throws {
    let json = Data(#"{ "name": "cerebral-helm", "default_branch": "prod" }"#.utf8)
    #expect(try GitHubAPIStatusProvider.parseDefaultBranch(json) == "prod")
}

private let gitHubAPITestURL = URL(string: "https://api.github.com/repos/o/r/pulls")!

private func gitHubAPIResponse(status: Int, headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: gitHubAPITestURL, statusCode: status, httpVersion: nil, headerFields: headers)!
}

@Test("a 403 with X-RateLimit-Remaining 0 maps to rateLimited with the reset instant")
func gitHubAPIRateLimitDetected() {
    let http = gitHubAPIResponse(
        status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"]
    )
    #expect(GitHubAPIStatusProvider.rateLimitError(from: http) == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_700_000_000)))
}

@Test("a 200, or a 403 with remaining budget, is not a rate limit")
func gitHubAPIRateLimitNotTriggered() {
    let ok = gitHubAPIResponse(status: 200, headers: ["X-RateLimit-Remaining": "0"])
    #expect(GitHubAPIStatusProvider.rateLimitError(from: ok) == nil)

    let hasBudget = gitHubAPIResponse(status: 403, headers: ["X-RateLimit-Remaining": "42"])
    #expect(GitHubAPIStatusProvider.rateLimitError(from: hasBudget) == nil)
}
#endif
