import Foundation

/// The local branch's relationship to its `origin` remote-tracking ref (NIC-130), derived by
/// comparing ref SHAs — never a numeric count. The raw values match the `project-git-status`
/// widget payload strings by construction, so the runtime-host mapping (Increment 3) is trivial.
public enum GitSyncState: String, Equatable, Sendable {
    /// The local branch tip equals `origin/<branch>`.
    case synced
    /// The local branch tip differs from `origin/<branch>`. Direction is deliberately not claimed
    /// (ahead vs behind would require a commit-graph walk); "diverged" is the honest categorical.
    case diverged
    /// There is no `origin/<branch>` remote-tracking ref — an unpushed branch.
    case noUpstream = "no-upstream"
}

/// A repository's current branch and its sync state (NIC-130). `branch` is `nil` when HEAD is
/// detached or unresolvable; `sync` is `nil` when there is no local branch to compare (a detached
/// HEAD, or an unreadable repo).
public struct GitBranchStatus: Equatable, Sendable {
    public let branch: String?
    public let sync: GitSyncState?

    public init(branch: String?, sync: GitSyncState?) {
        self.branch = branch
        self.sync = sync
    }
}

/// Reads a repository's current branch and its relationship to `origin/<branch>` by reading `.git`
/// files directly — `HEAD`, the loose refs under `refs/`, and `packed-refs` (NIC-130). Portable and
/// deterministic: no process is spawned. The sync state reflects the **last local fetch** (the
/// remote-tracking ref), not the live remote — the widget states this honestly.
///
/// The upstream is taken to be `origin/<same-branch>` (the owner's decision), not the per-branch
/// upstream configured in `[branch]`; this matches ``GitRemoteResolver``, which reads `origin`.
public struct GitSyncReader: Sendable {
    public init() {}

    /// The branch/sync status for the repository at `repository`. An unreadable repo (no `.git`)
    /// yields an empty status (`branch` and `sync` both `nil`), never an error.
    public func status(forRepositoryAt repository: URL) -> GitBranchStatus {
        guard let gitDirectory = GitDirectory.locate(forRepositoryAt: repository) else {
            return GitBranchStatus(branch: nil, sync: nil)
        }

        switch Self.head(inGitDirectory: gitDirectory) {
        case let .branch(name):
            let local = Self.resolveRef("refs/heads/\(name)", inGitDirectory: gitDirectory)
            let upstream = Self.resolveRef("refs/remotes/origin/\(name)", inGitDirectory: gitDirectory)
            let sync: GitSyncState
            if upstream == nil {
                sync = .noUpstream
            } else if let local, local == upstream {
                sync = .synced
            } else {
                sync = .diverged
            }
            return GitBranchStatus(branch: name, sync: sync)
        case let .detached(shortSHA):
            // A detached HEAD has no branch to compare — show the short SHA (as NIC-131 does), no sync.
            return GitBranchStatus(branch: shortSHA, sync: nil)
        case .none:
            return GitBranchStatus(branch: nil, sync: nil)
        }
    }

    // MARK: - HEAD / ref reading (internal for @testable unit tests)

    /// What a repository's `HEAD` points at.
    enum Head: Equatable {
        /// A local branch: `ref: refs/heads/<name>`.
        case branch(String)
        /// A detached HEAD (a raw commit SHA), carried as a 7-char short SHA.
        case detached(String)
        /// Unresolvable or a symbolic ref that isn't a local branch.
        case none
    }

    static func head(inGitDirectory gitDirectory: URL) -> Head {
        let headURL = gitDirectory.appendingPathComponent("HEAD", isDirectory: false)
        guard let raw = try? String(contentsOf: headURL, encoding: .utf8) else { return .none }
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return .none }

        let branchPrefix = "ref: refs/heads/"
        if head.hasPrefix(branchPrefix) {
            let name = String(head.dropFirst(branchPrefix.count))
            return name.isEmpty ? .none : .branch(name)
        }
        if isHexSHA(head) {
            return .detached(String(head.prefix(7)))
        }
        // A symbolic ref that isn't a local branch (a tag or remote ref): no branch, no sync.
        return .none
    }

    /// Resolves a ref (e.g. `refs/heads/main`) to its commit SHA, or `nil` when it doesn't exist.
    /// Checks the loose ref file first (following a single symbolic `ref:` indirection), then
    /// `packed-refs`. Peeled tag lines (`^…`) and comments (`#…`) in `packed-refs` are ignored.
    static func resolveRef(_ ref: String, inGitDirectory gitDirectory: URL) -> String? {
        let looseURL = gitDirectory.appendingPathComponent(ref, isDirectory: false)
        if let raw = try? String(contentsOf: looseURL, encoding: .utf8) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let symbolicPrefix = "ref: "
            if value.hasPrefix(symbolicPrefix) {
                let target = String(value.dropFirst(symbolicPrefix.count)).trimmingCharacters(in: .whitespaces)
                return target == ref ? nil : resolveRef(target, inGitDirectory: gitDirectory)
            }
            if !value.isEmpty { return value }
        }

        let packedURL = gitDirectory.appendingPathComponent("packed-refs", isDirectory: false)
        guard let packed = try? String(contentsOf: packedURL, encoding: .utf8) else { return nil }
        for rawLine in packed.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("^") { continue }
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[1].trimmingCharacters(in: .whitespaces) == ref {
                return String(parts[0])
            }
        }
        return nil
    }

    private static func isHexSHA(_ value: String) -> Bool {
        value.count >= 7 && value.allSatisfy(\.isHexDigit)
    }
}
