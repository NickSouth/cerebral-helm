import Foundation
import Testing

import CerebralCore

/// NIC-131 Increment 2 (+ depth-2 revision): a deterministic reader that lists active git
/// repositories under a projects root, resolving each one's branch by reading `.git/HEAD`
/// directly (no process, no shell), ordered most-recently-active first and capped.
///
/// Layout (owner's organization): the root holds **project folders**; a project has a name
/// and a description and may or may not be a coding project, and the actual repositories live
/// one level below the project folder. So repos sit at `root/<project>/<repo>`.

private func temporaryProjectsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("active-repos-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Creates a repository at `root/<project>/<name>`. When `head` is nil the repo directory has
/// no `.git` at all (a plain folder inside the project). `gitAsFile` simulates a linked
/// worktree / submodule whose `.git` is a *file* pointing at the real git directory.
private func makeRepo(
    in root: URL,
    project: String,
    name: String,
    head: String?,
    modifiedAt: Date? = nil,
    gitAsFile: Bool = false
) throws {
    let fileManager = FileManager.default
    let projectDir = root.appendingPathComponent(project, isDirectory: true)
    let repo = projectDir.appendingPathComponent(name, isDirectory: true)
    try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
    guard let head else { return }

    let gitDirectory: URL
    if gitAsFile {
        // The real git directory is hidden (leading dot) so the enumerator's
        // skipsHiddenFiles never mistakes it for a repository of its own.
        gitDirectory = projectDir.appendingPathComponent(".gitstore-\(name)", isDirectory: true)
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

@Test("resolves attached branch names from HEAD one level below each project folder")
func resolvesAttachedBranches() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "CerebralHelm", name: "cerebral-helm", head: "ref: refs/heads/main\n")
    try makeRepo(in: root, project: "OnDraft", name: "web", head: "ref: refs/heads/feature/widgets\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    let branches = Dictionary(uniqueKeysWithValues: repos.map { ($0.name, $0.branch) })

    #expect(branches["cerebral-helm"] == "main")
    #expect(branches["web"] == "feature/widgets")
    let helm = repos.first { $0.name == "cerebral-helm" }
    #expect(helm?.path.hasSuffix("/CerebralHelm/cerebral-helm") == true)
    #expect(helm?.id == "CerebralHelm/cerebral-helm") // keyed by <project>/<repo>
}

@Test("a git repo directly under the root (a project that is itself a repo) is NOT listed")
func ignoresRepositoriesAtTheRootLevel() throws {
    let root = try temporaryProjectsRoot()
    // A `.git` directly inside a project folder (depth 1) — the project folder is never
    // treated as a repository; only its children are scanned.
    let projectDir = root.appendingPathComponent("legacy-top-level-repo", isDirectory: true)
    try FileManager.default.createDirectory(
        at: projectDir.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true
    )
    try "ref: refs/heads/main\n".write(
        to: projectDir.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8
    )
    // …and a real repo nested one level deeper.
    try makeRepo(in: root, project: "coding", name: "real", head: "ref: refs/heads/main\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.map(\.name) == ["real"])
}

@Test("a detached HEAD reports a short commit SHA, never a fabricated branch")
func detachedHeadReportsShortSHA() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "P", name: "detached", head: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.count == 1)
    #expect(repos[0].branch == "a1b2c3d")
}

@Test("an unresolvable HEAD lists the repo with no branch, rather than dropping it")
func unresolvableHeadListsRepoWithoutBranch() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "P", name: "garbled", head: "not a ref and not a sha\n")

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.count == 1)
    #expect(repos[0].name == "garbled")
    #expect(repos[0].branch == nil)
}

@Test("non-repo directories, loose files, and empty project folders are excluded")
func excludesNonRepos() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "coding", name: "real-repo", head: "ref: refs/heads/main\n")
    // A project folder whose child is not a repo.
    try makeRepo(in: root, project: "writing", name: "resume", head: nil)
    // A project folder with no children at all.
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("empty-project", isDirectory: true), withIntermediateDirectories: true
    )
    // A loose file directly under the root (not a project folder).
    try "notes".write(
        to: root.appendingPathComponent("loose-file.txt"), atomically: true, encoding: .utf8
    )

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.map(\.name) == ["real-repo"])
}

@Test("a .git file pointer (worktree / submodule) resolves HEAD from the linked git dir")
func resolvesGitFilePointer() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "P", name: "worktree", head: "ref: refs/heads/linked\n", gitAsFile: true)

    let repos = try FileSystemActiveReposProvider(root: root).activeRepositories()
    #expect(repos.map(\.name) == ["worktree"])
    #expect(repos[0].branch == "linked")
}

@Test("repositories are ordered most-recently-active first and capped by the limit")
func ordersByRecencyAndCaps() throws {
    let root = try temporaryProjectsRoot()
    try makeRepo(in: root, project: "A", name: "oldest", head: "ref: refs/heads/main\n",
                 modifiedAt: Date(timeIntervalSince1970: 1_000))
    try makeRepo(in: root, project: "B", name: "middle", head: "ref: refs/heads/main\n",
                 modifiedAt: Date(timeIntervalSince1970: 2_000))
    try makeRepo(in: root, project: "C", name: "newest", head: "ref: refs/heads/main\n",
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
