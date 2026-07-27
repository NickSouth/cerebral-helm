import Foundation
import Testing

@testable import CerebralCore

/// NIC-130 Increment 2: a deterministic reader that reports a repository's current branch and its
/// categorical sync state vs `origin/<branch>` by comparing ref SHAs read from `.git` (loose refs
/// and `packed-refs`) — no process, no numeric ahead/behind.

private let gitSyncShaA = String(repeating: "a", count: 40)
private let gitSyncShaB = String(repeating: "b", count: 40)

private func gitSyncTempRepo() throws -> URL {
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-sync-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: repo.appendingPathComponent(".git", isDirectory: true),
        withIntermediateDirectories: true
    )
    return repo
}

/// Writes a file under the repo's `.git`, creating intermediate ref directories as needed.
private func gitSyncWrite(_ text: String, to relativePath: String, in repo: URL) throws {
    let url = repo.appendingPathComponent(".git/\(relativePath)", isDirectory: false)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try text.write(to: url, atomically: true, encoding: .utf8)
}

@Test("reports synced when the local branch tip equals origin/<branch>")
func gitSyncSynced() throws {
    let repo = try gitSyncTempRepo()
    try gitSyncWrite("ref: refs/heads/main\n", to: "HEAD", in: repo)
    try gitSyncWrite("\(gitSyncShaA)\n", to: "refs/heads/main", in: repo)
    try gitSyncWrite("\(gitSyncShaA)\n", to: "refs/remotes/origin/main", in: repo)

    let status = GitSyncReader().status(forRepositoryAt: repo)
    #expect(status.branch == "main")
    #expect(status.sync == .synced)
}

@Test("reports diverged when the local branch tip differs from origin/<branch>")
func gitSyncDiverged() throws {
    let repo = try gitSyncTempRepo()
    try gitSyncWrite("ref: refs/heads/main\n", to: "HEAD", in: repo)
    try gitSyncWrite("\(gitSyncShaA)\n", to: "refs/heads/main", in: repo)
    try gitSyncWrite("\(gitSyncShaB)\n", to: "refs/remotes/origin/main", in: repo)

    #expect(GitSyncReader().status(forRepositoryAt: repo).sync == .diverged)
}

@Test("reports no-upstream when there is no origin/<branch> remote-tracking ref")
func gitSyncNoUpstream() throws {
    let repo = try gitSyncTempRepo()
    try gitSyncWrite("ref: refs/heads/feature/widgets\n", to: "HEAD", in: repo)
    try gitSyncWrite("\(gitSyncShaA)\n", to: "refs/heads/feature/widgets", in: repo)

    let status = GitSyncReader().status(forRepositoryAt: repo)
    #expect(status.branch == "feature/widgets") // nested branch names are kept whole
    #expect(status.sync == .noUpstream)
}

@Test("resolves refs from packed-refs when the loose ref files are absent")
func gitSyncPackedRefs() throws {
    let repo = try gitSyncTempRepo()
    try gitSyncWrite("ref: refs/heads/main\n", to: "HEAD", in: repo)
    try gitSyncWrite(
        """
        # pack-refs with: peeled fully-peeled sorted
        \(gitSyncShaA) refs/heads/main
        \(gitSyncShaA) refs/remotes/origin/main
        ^\(gitSyncShaB)
        """,
        to: "packed-refs",
        in: repo
    )

    #expect(GitSyncReader().status(forRepositoryAt: repo).sync == .synced)
}

@Test("a detached HEAD reports a short SHA as the branch and no sync state")
func gitSyncDetached() throws {
    let repo = try gitSyncTempRepo()
    try gitSyncWrite("\(gitSyncShaA)\n", to: "HEAD", in: repo)

    let status = GitSyncReader().status(forRepositoryAt: repo)
    #expect(status.branch == String(gitSyncShaA.prefix(7)))
    #expect(status.sync == nil)
}

@Test("an unreadable repository (no .git) reports an empty status, never an error")
func gitSyncNoGitDirectory() throws {
    let bare = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-sync-none-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)

    let status = GitSyncReader().status(forRepositoryAt: bare)
    #expect(status.branch == nil)
    #expect(status.sync == nil)
}
