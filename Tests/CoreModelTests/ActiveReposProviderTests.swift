import Foundation
import Testing

import CerebralCore

/// NIC-131 Increment 2: a deterministic reader that lists the active git repositories
/// under a projects root, resolving each one's branch by reading `.git/HEAD` directly
/// (no process, no shell), ordered most-recently-active first and capped.

private func temporaryProjectsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("active-repos-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Creates a repository directory under `root`. When `head` is nil the directory has no
/// `.git` at all (a plain, non-repo folder). `gitAsFile` simulates a linked worktree /
/// submodule whose `.git` is a *file* pointing at the real git directory.
private func makeRepo(
    in root: URL,
    name: String,
    head: String?,
    modifiedAt: Date? = nil,
    gitAsFile: Bool = false
) throws {
    let fileManager = FileManager.default
    let repo = root.appendingPathComponent(name, isDirectory: true)
    try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
    guard let head else { return }

    let gitDirectory: URL
    if gitAsFile {
        // The real git directory is hidden (leading dot) so the enumerator's
        // skipsHiddenFiles never mistakes it for a repository of its own.
        gitDirectory = root.appendingPathComponent(".gitstore-\(name)", isDirectory: true)
        try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try "gitdir: \(gitDirectory.path)\n"
            .write(to: repo.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    } else {
        gitDirectory = repo.appendingPathComponent(".git", isDirectory: true)
        try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    }

    let headURL = gitDirectory.appendingPathComponent("HEAD")
    try head.write(to: headURL, atomically: true, encoding: .utf8)
    if let modifiedAt {
        try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: headURL.path)
    }
}

@Test("resolves attached branch names from HEAD, keeping nested names whole")
func resolvesAttachedBranches() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "alpha", head: "ref: refs/heads/main\n")
    try makeRepo(in: root, name: "beta", head: "ref: refs/heads/feature/widgets\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    let branches = Dictionary(uniqueKeysWithValues: repos.map { ($0.name, $0.branch) })

    #expect(branches["alpha"] == "main")
    #expect(branches["beta"] == "feature/widgets")
    #expect(repos.first(where: { $0.name == "alpha" })?.path.hasSuffix("/alpha") == true)
}

@Test("a detached HEAD reports a short commit SHA, never a fabricated branch")
func detachedHeadReportsShortSHA() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "detached", head: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.count == 1)
    #expect(repos[0].branch == "a1b2c3d")
}

@Test("an unresolvable HEAD lists the repo with no branch, rather than dropping it")
func unresolvableHeadListsRepoWithoutBranch() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "garbled", head: "not a ref and not a sha\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.count == 1)
    #expect(repos[0].name == "garbled")
    #expect(repos[0].branch == nil)
}

@Test("non-repo directories and plain files are excluded")
func excludesNonRepos() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "real-repo", head: "ref: refs/heads/main\n")
    try makeRepo(in: root, name: "just-a-folder", head: nil) // no .git
    try "notes".write(
        to: root.appendingPathComponent("loose-file.txt"), atomically: true, encoding: .utf8
    )

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.map(\.name) == ["real-repo"])
}

@Test("a .git file pointer (worktree / submodule) resolves HEAD from the linked git dir")
func resolvesGitFilePointer() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "worktree", head: "ref: refs/heads/linked\n", gitAsFile: true)

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.map(\.name) == ["worktree"])
    #expect(repos[0].branch == "linked")
}

@Test("repositories are ordered most-recently-active first and capped by the limit")
func ordersByRecencyAndCaps() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, name: "oldest", head: "ref: refs/heads/main\n",
                 modifiedAt: Date(timeIntervalSince1970: 1_000))
    try makeRepo(in: root, name: "middle", head: "ref: refs/heads/main\n",
                 modifiedAt: Date(timeIntervalSince1970: 2_000))
    try makeRepo(in: root, name: "newest", head: "ref: refs/heads/main\n",
                 modifiedAt: Date(timeIntervalSince1970: 3_000))

    let ordered = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(ordered.map(\.name) == ["newest", "middle", "oldest"])

    let capped = try FileSystemActiveReposProvider(root: root, limit: 2).activeRepositories()
    #expect(capped.map(\.name) == ["newest", "middle"])
}

@Test("a readable but repo-less root returns empty; a missing root is unavailable")
func distinguishesEmptyFromUnavailable() throws {
    let emptyRoot = try temporaryProjectsRoot()
    #expect(try FileSystemActiveReposProvider(root: emptyRoot).activeRepositories().isEmpty)

    let missing = emptyRoot.appendingPathComponent("does-not-exist", isDirectory: true)
    #expect(throws: ActiveReposError.rootUnavailable(missing.path)) {
        _ = try FileSystemActiveReposProvider(root: missing).activeRepositories()
    }
}

@Test("the default projects root is ~/Projects")
func defaultProjectsRootIsHomeProjects() {
    let expected = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Projects", isDirectory: true)
        .standardizedFileURL
    #expect(WorkspacePaths.defaultProjectsRoot() == expected)
}
