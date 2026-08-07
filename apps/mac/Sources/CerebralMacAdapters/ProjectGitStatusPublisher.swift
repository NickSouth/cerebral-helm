// Streaming Project Git Status widget events (NIC-130) — the Developer left-slot producer.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// Enumerates the local repositories, resolves each one's branch/sync (from `.git`) and GitHub
/// remote (`origin`), fetches the read-only GitHub report per repo, and emits one
/// `widget.data.changed` event for the `project-git-status` widget per tick (NIC-130). The
/// dashboard folds it into `liveWidgets`, which the Developer left rail renders (NIC-131 blueprint).
///
/// Mirrors the sibling producers' battery/visibility discipline on a **slow cadence** (default
/// 10 min — repo status changes slowly and each tick makes several network requests per repo): the
/// loop is deactivated while the dashboard is not visible and reactivation emits immediately. The
/// token is read **per tick**, so a just-entered key takes effect on the next sample without a
/// relaunch; the shell also calls ``refresh()`` on that edit so the change is immediate.
///
/// Honesty is layered (never fabricated): the **local branch/sync always render** — the GitHub half
/// degrades independently per repo. A repo whose `origin` isn't GitHub shows local-only ("Not a
/// GitHub repository"); a repo with a GitHub remote but no stored token shows an "add your token"
/// sub-state; a per-repo GitHub failure degrades that repo's GitHub half without failing the widget;
/// an unreadable projects root makes the whole widget honestly "unavailable".
public actor ProjectGitStatusPublisher {
    private let repos: any ActiveReposProvider
    private let remoteResolver: GitRemoteResolver
    private let syncReader: GitSyncReader
    private let secretStore: any SecretStoreManaging
    private let github: any GitHubStatusProvider
    private let reference: String
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        repos: any ActiveReposProvider = FileSystemActiveReposProvider(),
        remoteResolver: GitRemoteResolver = GitRemoteResolver(),
        syncReader: GitSyncReader = GitSyncReader(),
        secretStore: any SecretStoreManaging,
        github: any GitHubStatusProvider,
        reference: String = "github_api_token",
        intervalMs: Int = 600_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.repos = repos
        self.remoteResolver = remoteResolver
        self.syncReader = syncReader
        self.secretStore = secretStore
        self.github = github
        self.reference = reference
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the widget
    /// populates as soon as the stream starts rather than after one (long) interval.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickIfActive()
                try? await Task.sleep(nanoseconds: self.intervalNanos)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Emit a fresh sample now, regardless of cadence — used when the user just stored the GitHub
    /// token (NIC-130), so the widget goes live immediately instead of waiting out the interval.
    /// The token is re-read this tick, so a newly entered key is picked up at once.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately
    /// instead of waiting out the current interval.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick()
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        let result: Swift.Result<[BridgeEventFactory.ProjectGitStatusInput], Error>
        do {
            let repositories = try repos.activeRepositories()
            // Resolve the token once per tick (one Keychain read). A missing/denied entry leaves it
            // nil → each GitHub-remote repo shows an honest "add your token" sub-state, while the
            // local branch/sync still render.
            let token = try? await secretStore.readValue(reference: reference)
            var inputs: [BridgeEventFactory.ProjectGitStatusInput] = []
            for repository in repositories {
                let repositoryURL = URL(fileURLWithPath: repository.path)
                let status = syncReader.status(forRepositoryAt: repositoryURL)
                let remote = remoteResolver.resolve(forRepositoryAt: repositoryURL)
                inputs.append(
                    BridgeEventFactory.ProjectGitStatusInput(
                        id: repository.id,
                        name: repository.name,
                        branch: status.branch,
                        sync: status.sync,
                        remote: remote,
                        github: await gitHubResult(remote: remote, branch: status.branch, token: token)
                    )
                )
            }
            result = .success(inputs)
        } catch {
            // The projects root couldn't be read → an honest "unavailable" widget, never empty.
            result = .failure(error)
        }

        let widget = BridgeEventFactory.projectGitStatusWidget(from: result, now: Date())
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: "project-git-status",
            widget: widget,
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }

    /// The GitHub report for one repo: `nil` when it has no GitHub remote (the web shows local-only);
    /// a `credentialsMissing` failure when it has a remote but no token is stored; otherwise the real
    /// fetch result (a per-repo failure is isolated — it degrades that repo's GitHub half, not the
    /// whole widget). `branch` seeds the CI/commits ref (the adapter falls back to the default branch
    /// when it isn't on the remote).
    private func gitHubResult(
        remote: GitRemote?, branch: String?, token: String?
    ) async -> Swift.Result<GitHubRepoReport, Error>? {
        guard let remote else { return nil }
        guard let token else { return .failure(GitHubStatusError.credentialsMissing) }
        do {
            let report = try await github.report(
                owner: remote.owner, repo: remote.repo, ref: branch ?? "", apiToken: token
            )
            return .success(report)
        } catch {
            return .failure(error)
        }
    }
}
#endif
