import Foundation
import Testing

import CerebralCore

/// NIC-130 Increment 3: the provider-neutral GitHub status port + its fixed-outcome mock. The real
/// REST adapter (Increment 4) is the only network-touching implementation; this covers the
/// contract's value types and the mock used by pre-Mac builds and tests.

private func gitHubReport() -> GitHubRepoReport {
    GitHubRepoReport(
        openPullRequests: GitHubOpenPullRequests(count: 2, titles: ["Repo status widget", "Weather"]),
        checks: .passing,
        recentCommits: [GitHubCommit(message: "fix: news formatting", shortSha: "320ac4c")]
    )
}

@Test("the mock provider yields the report it was constructed with, ignoring its inputs")
func gitHubMockReturnsReport() async throws {
    let provider = MockGitHubStatusProvider(report: gitHubReport())
    let report = try await provider.report(owner: "NickSouth", repo: "cerebral-helm", ref: "main", apiToken: "t")
    #expect(report == gitHubReport())
    #expect(report.checks == .passing)
    #expect(report.openPullRequests.count == 2)
}

@Test("the mock provider throws the credentials-missing error it was constructed with")
func gitHubMockThrowsCredentialsMissing() async {
    let provider = MockGitHubStatusProvider(error: .credentialsMissing)
    await #expect(throws: GitHubStatusError.credentialsMissing) {
        try await provider.report(owner: "o", repo: "r", ref: "main", apiToken: "")
    }
}

@Test("the rate-limited error carries its reset instant and compares by it")
func gitHubRateLimitedEquatable() {
    let reset = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(GitHubStatusError.rateLimited(resetAt: reset) == .rateLimited(resetAt: reset))
    #expect(GitHubStatusError.rateLimited(resetAt: reset) != .rateLimited(resetAt: nil))
}

@Test("checks-state raw values match the widget payload strings by construction")
func gitHubChecksStateRawValues() {
    #expect(GitHubChecksState.passing.rawValue == "passing")
    #expect(GitHubChecksState.failing.rawValue == "failing")
    #expect(GitHubChecksState.pending.rawValue == "pending")
    #expect(GitHubChecksState.none.rawValue == "none")
}
