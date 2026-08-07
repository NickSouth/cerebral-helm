import Foundation
import Testing

@testable import CerebralCore

/// NIC-130 Increment 2: a deterministic reader that resolves a repository's GitHub `owner/repo`
/// from the `origin` remote in `.git/config`, reading the file directly (no process). Non-GitHub
/// remotes and missing origins resolve to `nil` so the widget degrades to local-only state.

private func gitRemoteTempRepo() throws -> URL {
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-remote-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: repo.appendingPathComponent(".git", isDirectory: true),
        withIntermediateDirectories: true
    )
    return repo
}

private func gitRemoteWriteConfig(_ text: String, in repo: URL) throws {
    try text.write(
        to: repo.appendingPathComponent(".git/config", isDirectory: false),
        atomically: true,
        encoding: .utf8
    )
}

@Test("parses owner/repo from an https origin URL, with or without a .git suffix")
func gitRemoteHTTPS() {
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "https://github.com/NickSouth/cerebral-helm.git")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "https://github.com/NickSouth/cerebral-helm")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
}

@Test("parses owner/repo from https with embedded userinfo")
func gitRemoteHTTPSUserinfo() {
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "https://token@github.com/NickSouth/cerebral-helm.git")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
}

@Test("parses owner/repo from the scp-like and ssh:// SSH forms")
func gitRemoteSSH() {
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "git@github.com:NickSouth/cerebral-helm.git")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "ssh://git@github.com/NickSouth/cerebral-helm.git")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
    #expect(
        GitRemoteResolver.gitHubRemote(fromRemoteURL: "git://github.com/NickSouth/cerebral-helm.git")
            == GitRemote(owner: "NickSouth", repo: "cerebral-helm")
    )
}

@Test("rejects non-GitHub hosts and malformed URLs")
func gitRemoteRejectsNonGitHub() {
    #expect(GitRemoteResolver.gitHubRemote(fromRemoteURL: "https://gitlab.com/NickSouth/cerebral-helm.git") == nil)
    #expect(GitRemoteResolver.gitHubRemote(fromRemoteURL: "git@bitbucket.org:NickSouth/cerebral-helm.git") == nil)
    #expect(GitRemoteResolver.gitHubRemote(fromRemoteURL: "https://github.com/NickSouth") == nil) // no repo segment
    #expect(GitRemoteResolver.gitHubRemote(fromRemoteURL: "not a url") == nil)
    #expect(GitRemoteResolver.gitHubRemote(fromRemoteURL: "") == nil)
}

@Test("picks the origin url among several remotes and stops at the next section")
func gitRemoteOriginAmongRemotes() {
    let config = """
    [core]
    \trepositoryformatversion = 0
    [remote "upstream"]
    \turl = https://github.com/other/repo.git
    [remote "origin"]
    \turl = git@github.com:NickSouth/cerebral-helm.git
    \tfetch = +refs/heads/*:refs/remotes/origin/*
    [branch "main"]
    \tremote = origin
    """
    #expect(GitRemoteResolver.originURL(inConfig: config) == "git@github.com:NickSouth/cerebral-helm.git")
}

@Test("returns nil when there is no origin remote in the config")
func gitRemoteNoOrigin() {
    let config = """
    [core]
    \trepositoryformatversion = 0
    [remote "upstream"]
    \turl = https://github.com/other/repo.git
    """
    #expect(GitRemoteResolver.originURL(inConfig: config) == nil)
}

@Test("resolves the GitHub remote from a repository's .git/config on disk")
func gitRemoteResolvesFromDisk() throws {
    let repo = try gitRemoteTempRepo()
    try gitRemoteWriteConfig(
        """
        [remote "origin"]
        \turl = https://github.com/NickSouth/cerebral-helm.git
        """,
        in: repo
    )
    #expect(GitRemoteResolver().resolve(forRepositoryAt: repo) == GitRemote(owner: "NickSouth", repo: "cerebral-helm"))
}

@Test("resolves to nil for a repository with no .git at all")
func gitRemoteNoGitDirectory() throws {
    let bare = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-remote-none-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
    #expect(GitRemoteResolver().resolve(forRepositoryAt: bare) == nil)
}
