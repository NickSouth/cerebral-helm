import Foundation

/// The collapsed CI state for a repository's latest commit (NIC-130). The raw values match the
/// `project-git-status` widget payload strings by construction, so the runtime-host mapping is
/// trivial. `none` is a first-class, tidy state — the repository simply has no CI — and is
/// distinct from the GitHub section being unavailable or rate-limited (a reachability problem).
public enum GitHubChecksState: String, Equatable, Sendable {
    case passing
    case failing
    case pending
    case none
}

/// The open pull requests for a repository (NIC-130): a count plus the titles the widget lists.
/// `titles` may be a prefix of `count` (the provider need not return every title); the count is
/// authoritative for the summary line.
public struct GitHubOpenPullRequests: Equatable, Sendable {
    public let count: Int
    public let titles: [String]

    public init(count: Int, titles: [String]) {
        self.count = count
        self.titles = titles
    }
}

/// One recent commit for a repository's report (NIC-130): the message plus a short SHA.
public struct GitHubCommit: Equatable, Sendable {
    public let message: String
    public let shortSha: String

    public init(message: String, shortSha: String) {
        self.message = message
        self.shortSha = shortSha
    }
}

/// The read-only GitHub half of a repository's report (NIC-130): open PRs, CI state, and recent
/// commits for a given ref. Provider-neutral — a concrete provider (the REST adapter, Increment 4)
/// maps its own responses onto these fields.
public struct GitHubRepoReport: Equatable, Sendable {
    public let openPullRequests: GitHubOpenPullRequests
    public let checks: GitHubChecksState
    public let recentCommits: [GitHubCommit]

    public init(openPullRequests: GitHubOpenPullRequests, checks: GitHubChecksState, recentCommits: [GitHubCommit]) {
        self.openPullRequests = openPullRequests
        self.checks = checks
        self.recentCommits = recentCommits
    }
}

/// Why a GitHub report could not be produced (NIC-130). Kept coarse and provider-neutral: the
/// event mapping degrades any failure to an honest GitHub sub-state, distinguishing a missing
/// credential (guide the user to add a token), a rate limit (surfaced distinctly so the user
/// knows to wait), and any other provider/network failure. FR-CFG-03/FR-SAF-07: the raw
/// diagnostic is never surfaced. ``credentialsMissing`` is thrown by the publisher when the
/// Keychain reference is unbound (Increment 6) — the provider itself reports the network cases.
public enum GitHubStatusError: Error, Equatable, Sendable {
    /// No GitHub token is configured — the widget should guide the user to add one.
    case credentialsMissing
    /// GitHub's rate limit was hit; `resetAt` is when it lifts, when the response reported it.
    case rateLimited(resetAt: Date?)
    /// The provider or network failed, or returned an unparseable response.
    case providerFailed(String)
}

/// Port that fetches a repository's read-only GitHub status (NIC-130). Provider-neutral and
/// credential-driven: the caller (the ``ProjectGitStatusPublisher``, Increment 6) resolves the
/// token from the Keychain and passes it in, so this contract never touches the secret store.
/// `ref` is the branch to report CI and commits for (the local branch, falling back to the
/// repository default upstream — the adapter, Increment 4, handles the fallback). Async because
/// a real provider performs network fetches; the mock resolves synchronously. Throws
/// ``GitHubStatusError`` on failure — the mapping treats it as an honest GitHub sub-state, never
/// a fabricated report.
public protocol GitHubStatusProvider: Sendable {
    func report(owner: String, repo: String, ref: String, apiToken: String) async throws -> GitHubRepoReport
}

/// A fixed-outcome ``GitHubStatusProvider`` for pre-Mac builds and tests: it ignores its inputs
/// and always yields the report (or throws the error) it was constructed with.
public struct MockGitHubStatusProvider: GitHubStatusProvider {
    private let outcome: Result<GitHubRepoReport, GitHubStatusError>

    public init(report: GitHubRepoReport) {
        self.outcome = .success(report)
    }

    public init(error: GitHubStatusError) {
        self.outcome = .failure(error)
    }

    public func report(owner: String, repo: String, ref: String, apiToken: String) async throws -> GitHubRepoReport {
        try outcome.get()
    }
}
