// NIC-130 Increment 6: streaming the project-git-status widget as widget.data.changed events,
// composed from local .git state (branch/sync/remote) and a Keychain-resolved GitHub report.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralTools

private final class PGSEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

private func waitForPGS(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

/// A fixed-list ``ActiveReposProvider`` for tests — yields the repositories it was built with, or
/// throws to simulate an unreadable projects root.
private struct PGSMockReposProvider: ActiveReposProvider {
    let outcome: Swift.Result<[RepoStatus], ActiveReposError>
    init(_ repos: [RepoStatus]) { outcome = .success(repos) }
    init(error: ActiveReposError) { outcome = .failure(error) }
    func activeRepositories() throws -> [RepoStatus] { try outcome.get() }
}

private let pgsShaA = String(repeating: "a", count: 40)
private let pgsShaB = String(repeating: "b", count: 40)

/// Builds a temp repository with real `.git` state so ``GitRemoteResolver`` and ``GitSyncReader``
/// resolve genuine remote/branch/sync from it. `origin` nil → no remote; `originSHA` nil → no
/// upstream. `branch` must be a simple name (no `/`) so the loose ref is a single file.
private func pgsRepo(origin: String?, branch: String, localSHA: String, originSHA: String?) throws -> URL {
    let fileManager = FileManager.default
    let repo = fileManager.temporaryDirectory.appendingPathComponent("pgs-\(UUID().uuidString)", isDirectory: true)
    let git = repo.appendingPathComponent(".git", isDirectory: true)
    try fileManager.createDirectory(at: git, withIntermediateDirectories: true)
    if let origin {
        try "[remote \"origin\"]\n\turl = \(origin)\n"
            .write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }
    try "ref: refs/heads/\(branch)\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
    let heads = git.appendingPathComponent("refs/heads", isDirectory: true)
    try fileManager.createDirectory(at: heads, withIntermediateDirectories: true)
    try "\(localSHA)\n".write(to: heads.appendingPathComponent(branch), atomically: true, encoding: .utf8)
    if let originSHA {
        let remotes = git.appendingPathComponent("refs/remotes/origin", isDirectory: true)
        try fileManager.createDirectory(at: remotes, withIntermediateDirectories: true)
        try "\(originSHA)\n".write(to: remotes.appendingPathComponent(branch), atomically: true, encoding: .utf8)
    }
    return repo
}

private func pgsRepoStatus(_ url: URL, name: String) -> RepoStatus {
    RepoStatus(id: name, name: name, branch: nil, path: url.path, lastActivityAt: .distantPast)
}

private func pgsReport() -> GitHubRepoReport {
    GitHubRepoReport(
        openPullRequests: GitHubOpenPullRequests(count: 2, titles: ["Repo status widget"]),
        checks: .passing,
        recentCommits: [GitHubCommit(message: "fix: news formatting", shortSha: "320ac4c")]
    )
}

@Test("with a GitHub remote and a stored token the publisher emits a ready report; the token never leaks")
func pgsPublisherEmitsReady() async throws {
    let repo = try pgsRepo(
        origin: "https://github.com/NickSouth/cerebral-helm.git",
        branch: "main", localSHA: pgsShaA, originSHA: pgsShaA // equal → synced
    )
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "cerebral-helm")]),
        secretStore: MockSecretStore(values: ["github_api_token": "ghp_tok"]),
        github: MockGitHubStatusProvider(report: pgsReport()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .widgetDataChanged)
    let json = collector.all[0]
    #expect(json.contains("\"widgetId\":\"project-git-status\""))
    #expect(json.contains("\"state\":\"ready\""))
    #expect(json.contains("\"name\":\"cerebral-helm\""))
    #expect(json.contains("\"sync\":\"synced\"")) // resolved from the equal ref SHAs
    #expect(json.contains("\"owner\":\"NickSouth\""))
    #expect(json.contains("Repo status widget")) // the PR title from the GitHub report
    #expect(!json.contains("ghp_tok")) // the token is never part of the emitted event
}

@Test("a repo whose origin isn't GitHub renders local-only — no remote or github section")
func pgsPublisherLocalOnlyForNonGitHub() async throws {
    let repo = try pgsRepo(origin: nil, branch: "wip", localSHA: pgsShaA, originSHA: nil)
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "scratchpad")]),
        secretStore: MockSecretStore(values: ["github_api_token": "ghp_tok"]),
        github: MockGitHubStatusProvider(report: pgsReport()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    let json = collector.all[0]
    #expect(json.contains("\"state\":\"ready\""))
    #expect(json.contains("\"sync\":\"no-upstream\"")) // local sync still renders
    #expect(!json.contains("\"github\"")) // no GitHub section for a non-GitHub remote
    #expect(!json.contains("\"remote\""))
}

@Test("a GitHub remote with no stored token shows an add-your-token sub-state, keeping local sync")
func pgsPublisherNoToken() async throws {
    let repo = try pgsRepo(
        origin: "git@github.com:NickSouth/cerebral-helm.git",
        branch: "main", localSHA: pgsShaA, originSHA: pgsShaB // differ → diverged
    )
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "cerebral-helm")]),
        secretStore: MockSecretStore(), // no token bound
        github: MockGitHubStatusProvider(report: pgsReport()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    let json = collector.all[0]
    #expect(json.contains("\"state\":\"ready\"")) // the widget is ready (local data present)
    #expect(json.contains("\"sync\":\"diverged\""))
    #expect(json.contains("GitHub token")) // the github sub-state guides the user to add a token
}

@Test("a per-repo GitHub failure degrades that repo's github half without leaking the diagnostic")
func pgsPublisherGitHubFailure() async throws {
    let repo = try pgsRepo(
        origin: "https://github.com/NickSouth/cerebral-helm.git",
        branch: "main", localSHA: pgsShaA, originSHA: pgsShaA
    )
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "cerebral-helm")]),
        secretStore: MockSecretStore(values: ["github_api_token": "ghp_tok"]),
        github: MockGitHubStatusProvider(error: .providerFailed("HTTP 500 ghp_tok")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    let json = collector.all[0]
    #expect(json.contains("\"state\":\"ready\"")) // local data keeps the widget ready
    #expect(!json.contains("HTTP 500")) // the raw diagnostic is never surfaced
    #expect(!json.contains("GitHub token")) // not the credentials message either
}

@Test("a rate limit maps the repo's github half to a distinct rate-limited sub-state")
func pgsPublisherRateLimited() async throws {
    let repo = try pgsRepo(
        origin: "https://github.com/NickSouth/cerebral-helm.git",
        branch: "main", localSHA: pgsShaA, originSHA: pgsShaA
    )
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "cerebral-helm")]),
        secretStore: MockSecretStore(values: ["github_api_token": "ghp_tok"]),
        github: MockGitHubStatusProvider(error: .rateLimited(resetAt: nil)),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.all[0].contains("\"state\":\"rate-limited\""))
}

@Test("an unreadable projects root emits an honest unavailable widget")
func pgsPublisherRootUnavailable() async throws {
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider(error: .rootUnavailable("/nope")),
        secretStore: MockSecretStore(values: ["github_api_token": "ghp_tok"]),
        github: MockGitHubStatusProvider(report: pgsReport()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
}

@Test("a paused project-git-status publisher emits nothing; resuming emits immediately")
func pgsPublisherPauseResume() async throws {
    let repo = try pgsRepo(origin: nil, branch: "main", localSHA: pgsShaA, originSHA: nil)
    let collector = PGSEventCollector()
    let publisher = ProjectGitStatusPublisher(
        repos: PGSMockReposProvider([pgsRepoStatus(repo, name: "notes")]),
        secretStore: MockSecretStore(),
        github: MockGitHubStatusProvider(report: pgsReport()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForPGS(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitForPGS(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
