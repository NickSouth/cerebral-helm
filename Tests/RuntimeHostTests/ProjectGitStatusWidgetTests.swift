import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-130 Increment 3: mapping the per-repo Project Git Status inputs into the widget envelope,
/// and emitting it as a `widget.data.changed` bridge event (the NIC-131 live-widget pipe). The
/// local branch/sync always render; the GitHub half degrades independently per repo. Test funcs
/// are prefixed `projectGit` because Swift test targets share a module-global namespace.

private let projectGitNow = Date(timeIntervalSince1970: 1_700_000_000)

private func projectGitReport() -> GitHubRepoReport {
    GitHubRepoReport(
        openPullRequests: GitHubOpenPullRequests(count: 2, titles: ["Repo status widget", "Weather"]),
        checks: .passing,
        recentCommits: [GitHubCommit(message: "fix: news formatting", shortSha: "320ac4c")]
    )
}

private func projectGitInput(
    _ id: String, _ name: String, branch: String?, sync: GitSyncState?,
    remote: GitRemote?, github: Swift.Result<GitHubRepoReport, Error>?
) -> BridgeEventFactory.ProjectGitStatusInput {
    BridgeEventFactory.ProjectGitStatusInput(
        id: id, name: name, branch: branch, sync: sync, remote: remote, github: github
    )
}

@Test("a ready repo maps to branch, sync, PRs, CI, and commits")
func projectGitReadyMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "cerebral-helm", "cerebral-helm", branch: "main", sync: .diverged,
                remote: GitRemote(owner: "NickSouth", repo: "cerebral-helm"),
                github: .success(projectGitReport())
            )
        ]),
        now: projectGitNow
    )

    #expect(widget.widgetId == "project-git-status")
    #expect(widget.state == "ready")
    #expect(widget.headline == "1 repository")
    #expect(widget.freshness?.observedAt == projectGitNow)

    let item = widget.data?.repositories.first
    #expect(item?.branch == "main")
    #expect(item?.sync == "diverged") // categorical rawValue, never a numeric count
    #expect(item?.remote?.owner == "NickSouth")
    #expect(item?.github?.state == "ready")
    #expect(item?.github?.openPullRequests?.count == 2)
    #expect(item?.github?.checks?.state == "passing")
    #expect(item?.github?.recentCommits?.first?.shortSha == "320ac4c")
    #expect(item?.github?.message == nil)
}

@Test("a repo with no CI maps checks to none, never failing")
func projectGitNoCIMapping() {
    let report = GitHubRepoReport(
        openPullRequests: GitHubOpenPullRequests(count: 0, titles: []),
        checks: .none,
        recentCommits: []
    )
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "notes", "notes", branch: "main", sync: .synced,
                remote: GitRemote(owner: "NickSouth", repo: "notes"),
                github: .success(report)
            )
        ]),
        now: projectGitNow
    )
    #expect(widget.data?.repositories.first?.github?.checks?.state == "none")
}

@Test("a repo with no GitHub remote omits the github section but keeps local branch/sync")
func projectGitNoRemoteMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "scratchpad", "scratchpad", branch: "wip", sync: .noUpstream,
                remote: nil, github: nil
            )
        ]),
        now: projectGitNow
    )
    let item = widget.data?.repositories.first
    #expect(item?.branch == "wip")
    #expect(item?.sync == "no-upstream")
    #expect(item?.remote == nil)
    #expect(item?.github == nil)
}

@Test("a missing credential maps the github half to unavailable with add-token guidance")
func projectGitCredentialsMissingMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "cerebral-helm", "cerebral-helm", branch: "main", sync: .synced,
                remote: GitRemote(owner: "NickSouth", repo: "cerebral-helm"),
                github: .failure(GitHubStatusError.credentialsMissing)
            )
        ]),
        now: projectGitNow
    )
    let github = widget.data?.repositories.first?.github
    #expect(github?.state == "unavailable")
    #expect(github?.message?.contains("GitHub token") == true)
    #expect(github?.openPullRequests == nil)
    // The local branch/sync still render even when GitHub can't be read.
    #expect(widget.data?.repositories.first?.branch == "main")
}

@Test("a rate limit maps the github half to a distinct rate-limited state")
func projectGitRateLimitedMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "cerebral-helm", "cerebral-helm", branch: "main", sync: .synced,
                remote: GitRemote(owner: "NickSouth", repo: "cerebral-helm"),
                github: .failure(GitHubStatusError.rateLimited(resetAt: projectGitNow))
            )
        ]),
        now: projectGitNow
    )
    #expect(widget.data?.repositories.first?.github?.state == "rate-limited")
}

@Test("a provider failure maps to a generic unavailable, never leaking the diagnostic")
func projectGitProviderFailureMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "cerebral-helm", "cerebral-helm", branch: "main", sync: .synced,
                remote: GitRemote(owner: "NickSouth", repo: "cerebral-helm"),
                github: .failure(GitHubStatusError.providerFailed("HTTP 500 secret-token"))
            )
        ]),
        now: projectGitNow
    )
    let github = widget.data?.repositories.first?.github
    #expect(github?.state == "unavailable")
    #expect(github?.message?.contains("HTTP 500") == false)
    #expect(github?.message?.contains("secret-token") == false)
}

@Test("a read failure maps to an unavailable widget")
func projectGitRootFailureMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .failure(ActiveReposError.rootUnavailable("/x")), now: projectGitNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
}

@Test("a readable-but-empty root maps to an empty widget")
func projectGitEmptyMapping() {
    let widget = BridgeEventFactory.projectGitStatusWidget(from: .success([]), now: projectGitNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.freshness == nil)
}

@Test("the widget emits as a widget.data.changed event; nil fields are omitted, not null")
func projectGitEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.projectGitStatusWidget(
        from: .success([
            projectGitInput(
                "cerebral-helm", "cerebral-helm", branch: "main", sync: .diverged,
                remote: GitRemote(owner: "NickSouth", repo: "cerebral-helm"),
                github: .success(projectGitReport())
            ),
            projectGitInput(
                "scratchpad", "scratchpad", branch: "wip", sync: .noUpstream, remote: nil, github: nil
            )
        ]),
        now: projectGitNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "project-git-status", widget: widget, id: "brevt_test00000130", timestamp: projectGitNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"project-git-status\""))
    #expect(json.contains("\"sync\":\"diverged\""))
    #expect(json.contains("\"sync\":\"no-upstream\""))
    // The local-only repo omits remote/github rather than encoding explicit nulls.
    #expect(!json.contains("\"remote\":null"))
    #expect(!json.contains("\"github\":null"))

    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000130")
}
