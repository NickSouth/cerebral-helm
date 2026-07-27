// Read-only GitHub repository status from the REST API (NIC-130).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore

/// Fetches a repository's read-only GitHub status (open PRs, CI, recent commits) from the REST API
/// (`api.github.com`) with `URLSession`. The personal access token is supplied per call (resolved
/// from the Keychain by the ``ProjectGitStatusPublisher``, Increment 6) and sent in the
/// **`Authorization: Bearer` header** — never in the URL, so it can't leak into logs (FR-OBS-03).
/// Mirrors the read-only ephemeral-`URLSession` pattern the weather/releases/stocks adapters use.
///
/// Three signals compose one ``GitHubRepoReport``:
/// - **Open PRs** — `GET /repos/{o}/{r}/pulls?state=open` (repo-wide).
/// - **CI** — `GET /repos/{o}/{r}/actions/runs?branch={ref}` (GitHub Actions; the token carries
///   `Actions: read`). The latest run collapses to passing/failing/pending, or `none` when the
///   branch has no runs — a repo without CI reads as complete, not broken.
/// - **Recent commits** — `GET /repos/{o}/{r}/commits?sha={ref}`.
///
/// `ref` is the local branch; when it isn't on the remote (an unpushed branch → 404) the commits
/// and CI fall back to the repository's `default_branch`. A `403`/`429` with `X-RateLimit-Remaining:
/// 0` maps to ``GitHubStatusError/rateLimited(resetAt:)``; any other transport/non-2xx/decode
/// failure maps to ``GitHubStatusError/providerFailed(_:)`` so the widget degrades honestly — never
/// a fabricated report.
public struct GitHubAPIStatusProvider: GitHubStatusProvider {
    private let session: URLSession
    private let host: String

    public init(
        session: URLSession? = nil,
        host: String = "https://api.github.com",
        resourceTimeout: TimeInterval = 15
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
    }

    public func report(owner: String, repo: String, ref: String, apiToken: String) async throws -> GitHubRepoReport {
        do {
            // Open PRs first: repo-wide, and the auth / rate-limit probe for the whole report.
            let pullRequests = try await openPullRequests(owner: owner, repo: repo, apiToken: apiToken)
            let (effectiveRef, commits) = try await commitsResolvingRef(
                owner: owner, repo: repo, ref: ref, apiToken: apiToken
            )
            // CI is best-effort: a token without Actions access, or a repo with no runs, must not
            // fail the whole report — it degrades to `none` (no CI line) instead.
            let checks = (try? await checksState(
                owner: owner, repo: repo, branch: effectiveRef, apiToken: apiToken
            )) ?? .none
            return GitHubRepoReport(openPullRequests: pullRequests, checks: checks, recentCommits: commits)
        } catch let error as GitHubStatusError {
            throw error
        } catch is NotFound {
            // The repository (or its default branch) wasn't found — an inaccessible/private repo the
            // token can't see. Honest generic failure, never a fabricated report.
            throw GitHubStatusError.providerFailed("The repository was not found or is not accessible.")
        } catch {
            throw GitHubStatusError.providerFailed(error.localizedDescription)
        }
    }

    // MARK: - Endpoint calls

    private func openPullRequests(owner: String, repo: String, apiToken: String) async throws -> GitHubOpenPullRequests {
        let data = try await send(Self.makeRequest(
            host: host, path: "/repos/\(owner)/\(repo)/pulls",
            queryItems: [.init(name: "state", value: "open"), .init(name: "per_page", value: "30")],
            apiToken: apiToken
        ))
        return try Self.parsePullRequests(data)
    }

    /// Fetches recent commits for `ref`, falling back to the repository default branch when `ref`
    /// isn't on the remote (a `404`), or when `ref` is empty (a detached/unresolved local HEAD).
    /// Returns the ref that was actually used, so the CI query targets the same branch.
    private func commitsResolvingRef(
        owner: String, repo: String, ref: String, apiToken: String
    ) async throws -> (ref: String, commits: [GitHubCommit]) {
        if ref.isEmpty {
            let fallback = try await defaultBranch(owner: owner, repo: repo, apiToken: apiToken)
            return (fallback, (try? await recentCommits(owner: owner, repo: repo, ref: fallback, apiToken: apiToken)) ?? [])
        }
        do {
            return (ref, try await recentCommits(owner: owner, repo: repo, ref: ref, apiToken: apiToken))
        } catch is NotFound {
            let fallback = try await defaultBranch(owner: owner, repo: repo, apiToken: apiToken)
            return (fallback, (try? await recentCommits(owner: owner, repo: repo, ref: fallback, apiToken: apiToken)) ?? [])
        }
    }

    private func recentCommits(owner: String, repo: String, ref: String, apiToken: String) async throws -> [GitHubCommit] {
        let data = try await send(Self.makeRequest(
            host: host, path: "/repos/\(owner)/\(repo)/commits",
            queryItems: [.init(name: "sha", value: ref), .init(name: "per_page", value: "5")],
            apiToken: apiToken
        ))
        return try Self.parseCommits(data)
    }

    private func checksState(owner: String, repo: String, branch: String, apiToken: String) async throws -> GitHubChecksState {
        let data = try await send(Self.makeRequest(
            host: host, path: "/repos/\(owner)/\(repo)/actions/runs",
            queryItems: [.init(name: "branch", value: branch), .init(name: "per_page", value: "1")],
            apiToken: apiToken
        ))
        return try Self.checksState(fromActionsRuns: data)
    }

    private func defaultBranch(owner: String, repo: String, apiToken: String) async throws -> String {
        let data = try await send(Self.makeRequest(
            host: host, path: "/repos/\(owner)/\(repo)", queryItems: [], apiToken: apiToken
        ))
        return try Self.parseDefaultBranch(data)
    }

    // MARK: - Transport

    /// A `404` from a request, distinguished so the caller can fall back to the default branch.
    private struct NotFound: Error {}

    private func send(_ request: URLRequest?) async throws -> Data {
        guard let request else {
            throw GitHubStatusError.providerFailed("Could not build the GitHub request URL.")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubStatusError.providerFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GitHubStatusError.providerFailed("The GitHub service returned a non-HTTP response.")
        }
        if let limited = Self.rateLimitError(from: http) { throw limited }
        if http.statusCode == 404 { throw NotFound() }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubStatusError.providerFailed("The GitHub service returned HTTP \(http.statusCode).")
        }
        return data
    }

    // MARK: - Pure helpers (unit-tested)

    /// Builds a GitHub REST request. The token rides the `Authorization: Bearer` header — never the
    /// URL — so the secret can't appear in a logged/cached request URL (FR-OBS-03). Sends the
    /// recommended `Accept` and `X-GitHub-Api-Version` headers.
    static func makeRequest(host: String, path: String, queryItems: [URLQueryItem], apiToken: String) -> URLRequest? {
        guard var components = URLComponents(string: "\(host)\(path)") else { return nil }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// A JSON decoder that maps GitHub's snake_case keys (`default_branch`, `workflow_runs`) onto
    /// camelCase properties, so the response types need no `CodingKeys`.
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct PullRequestItem: Decodable { let title: String? }

    /// Parses the open-PRs list. `count` is the number returned (capped at the page size, 30 — a
    /// repo with more open PRs under-reports, which is acceptable for a glanceable widget); `titles`
    /// keeps the first few non-blank titles for the widget's list.
    static func parsePullRequests(_ data: Data) throws -> GitHubOpenPullRequests {
        let items: [PullRequestItem]
        do {
            items = try decoder().decode([PullRequestItem].self, from: data)
        } catch {
            throw GitHubStatusError.providerFailed("Could not parse the pull requests response.")
        }
        let titles = items.compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return GitHubOpenPullRequests(count: items.count, titles: Array(titles.prefix(5)))
    }

    private struct CommitItem: Decodable {
        let sha: String
        let commit: CommitDetail
        struct CommitDetail: Decodable { let message: String }
    }

    /// Parses recent commits: each row is the commit's **first message line** (the subject, not the
    /// body) plus a 7-char short SHA.
    static func parseCommits(_ data: Data) throws -> [GitHubCommit] {
        let items: [CommitItem]
        do {
            items = try decoder().decode([CommitItem].self, from: data)
        } catch {
            throw GitHubStatusError.providerFailed("Could not parse the commits response.")
        }
        return items.map { item in
            let subject = item.commit.message.split(whereSeparator: \.isNewline).first.map(String.init)
                ?? item.commit.message
            return GitHubCommit(
                message: subject.trimmingCharacters(in: .whitespaces),
                shortSha: String(item.sha.prefix(7))
            )
        }
    }

    private struct ActionsRunsResponse: Decodable {
        let workflowRuns: [Run]
        struct Run: Decodable {
            let status: String?
            let conclusion: String?
        }
    }

    /// Collapses the latest GitHub Actions run for a branch into a ``GitHubChecksState``. No runs →
    /// `none` (the branch has no CI). A run still going (`status != "completed"`) → `pending`. A
    /// completed run → `passing`/`failing` by conclusion; an inconclusive conclusion (cancelled,
    /// skipped, neutral, stale, or none) → `none`, so the widget only ever claims pass/fail when the
    /// signal is definitive.
    static func checksState(fromActionsRuns data: Data) throws -> GitHubChecksState {
        let decoded: ActionsRunsResponse
        do {
            decoded = try decoder().decode(ActionsRunsResponse.self, from: data)
        } catch {
            throw GitHubStatusError.providerFailed("Could not parse the Actions runs response.")
        }
        guard let run = decoded.workflowRuns.first else { return .none }
        guard run.status == "completed" else { return .pending }
        switch run.conclusion {
        case "success":
            return .passing
        case "failure", "timed_out", "startup_failure", "action_required":
            return .failing
        default:
            return .none
        }
    }

    private struct RepoResponse: Decodable { let defaultBranch: String }

    static func parseDefaultBranch(_ data: Data) throws -> String {
        do {
            return try decoder().decode(RepoResponse.self, from: data).defaultBranch
        } catch {
            throw GitHubStatusError.providerFailed("Could not parse the repository response.")
        }
    }

    /// A rate-limit error when the response is a `403`/`429` with the primary-rate-limit signal
    /// (`X-RateLimit-Remaining: 0`), carrying the reset instant from `X-RateLimit-Reset` when present.
    /// Header lookup is case-insensitive on `HTTPURLResponse`.
    static func rateLimitError(from http: HTTPURLResponse) -> GitHubStatusError? {
        guard http.statusCode == 403 || http.statusCode == 429 else { return nil }
        guard http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" else { return nil }
        let resetAt = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) }
        return .rateLimited(resetAt: resetAt)
    }
}
#endif
