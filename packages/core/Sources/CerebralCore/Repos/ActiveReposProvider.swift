import Foundation

/// One active repository under the user's projects root (NIC-131). Produced by
/// ``ActiveReposProvider`` and mapped to the `repositories` widget's payload by the live
/// producer (Increment 3). `branch` is `nil` when the local repo's HEAD can't be resolved
/// to a name — never fabricated. `path` is the absolute repository directory the
/// click-to-open action (`project.open`, Increment 4) targets.
public struct RepoStatus: Equatable, Sendable {
    /// Stable identity within the root: the repository directory name.
    public let id: String
    /// Display name: the repository directory name.
    public let name: String
    /// Current branch, or `nil` when HEAD is unresolvable. A detached HEAD reports a
    /// short commit SHA (e.g. "a1b2c3d"), never a made-up branch name.
    public let branch: String?
    /// Absolute path of the repository directory.
    public let path: String
    /// When the repository was last active, taken from the mtime of its `HEAD` file.
    /// Drives the recency ordering and is available for a future freshness label.
    public let lastActivityAt: Date

    public init(id: String, name: String, branch: String?, path: String, lastActivityAt: Date) {
        self.id = id
        self.name = name
        self.branch = branch
        self.path = path
        self.lastActivityAt = lastActivityAt
    }
}

/// Why the projects root could not be read — distinct from "read fine, no repositories".
public enum ActiveReposError: Error, Equatable {
    /// The configured projects root does not exist or is not a readable directory. The
    /// producer maps this to an honest "unavailable" widget state, never an empty one.
    case rootUnavailable(String)
}

/// Port that lists the active git repositories under a configured projects root,
/// most-recently-active first (NIC-131). Portable and deterministic: it reads local
/// filesystem state only and never spawns a process. The live producer (Increment 3)
/// samples it; tests bind ``FileSystemActiveReposProvider`` against a temp directory.
public protocol ActiveReposProvider: Sendable {
    /// The active repositories under the root, newest first. Throws
    /// ``ActiveReposError/rootUnavailable(_:)`` when the root itself can't be read;
    /// returns an empty array when the root is readable but holds no git repositories.
    func activeRepositories() throws -> [RepoStatus]
}

/// Lists active repositories by reading local git state directly (the "read `.git/HEAD`
/// directly" decision, NIC-131): it walks the projects root two levels deep — each immediate
/// child of the root is a **project folder** (which has a name and a description and may or
/// may not contain code), and the actual git repositories live one level below that, inside
/// each project folder. It keeps the depth-2 directories that are git repositories and
/// resolves each one's branch from its `HEAD` file. No process is spawned and no shell is
/// invoked. Because branch names come straight out of `HEAD`, `packed-refs` is irrelevant
/// here — it would only be needed to resolve a ref to a commit SHA, which this does not do.
public struct FileSystemActiveReposProvider: ActiveReposProvider {
    private let root: URL
    private let limit: Int

    /// - Parameters:
    ///   - root: the projects root to scan (default ``WorkspacePaths/defaultProjectsRoot()``).
    ///   - limit: the maximum number of repositories to return (most-recent first).
    public init(root: URL = WorkspacePaths.defaultProjectsRoot(), limit: Int = 6) {
        self.root = root
        self.limit = max(0, limit)
    }

    public func activeRepositories() throws -> [RepoStatus] {
        let fileManager = FileManager.default

        var rootIsDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
            rootIsDirectory.boolValue,
            let projectFolders = subdirectories(of: root)
        else {
            throw ActiveReposError.rootUnavailable(root.path)
        }

        var repos: [RepoStatus] = []
        for projectFolder in projectFolders {
            // Repositories live one level below each project folder (NIC-131): a project has a
            // name + description and may contain a repo, but need not be one itself, so the
            // project folder is never treated as a repository — only its children are.
            for candidate in subdirectories(of: projectFolder) ?? [] {
                guard let headURL = resolvedHeadURL(forRepositoryAt: candidate) else { continue }
                let name = candidate.lastPathComponent
                repos.append(
                    RepoStatus(
                        // Keyed by <project>/<repo> so two projects with same-named repos stay distinct.
                        id: "\(projectFolder.lastPathComponent)/\(name)",
                        name: name,
                        branch: branch(fromHeadAt: headURL),
                        path: candidate.standardizedFileURL.path,
                        lastActivityAt: modificationDate(of: headURL)
                    )
                )
            }
        }

        // Most-recently-active first; ties break on name for a stable, deterministic order.
        repos.sort { lhs, rhs in
            lhs.lastActivityAt == rhs.lastActivityAt
                ? lhs.name < rhs.name
                : lhs.lastActivityAt > rhs.lastActivityAt
        }
        return Array(repos.prefix(limit))
    }

    // MARK: - Filesystem helpers

    /// The immediate subdirectories of `directory` (visible only), or `nil` when it can't be
    /// listed. `nil` on the root is `rootUnavailable`; `nil` on a project folder just skips it.
    private func subdirectories(of directory: URL) -> [URL]? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries.filter { isDirectory($0) }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Resolves the `HEAD` file for a candidate directory, or `nil` when it isn't a git
    /// repository. Handles both a normal `.git` directory and a `.git` *file* pointer
    /// (linked worktrees and submodules), whose `gitdir:` line names the real git dir.
    private func resolvedHeadURL(forRepositoryAt repository: URL) -> URL? {
        let fileManager = FileManager.default
        let gitPath = repository.appendingPathComponent(".git", isDirectory: false)
        var gitIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitPath.path, isDirectory: &gitIsDirectory) else {
            return nil
        }

        let gitDirectory: URL
        if gitIsDirectory.boolValue {
            gitDirectory = gitPath
        } else if let resolved = linkedGitDirectory(fromPointerFileAt: gitPath, repository: repository) {
            gitDirectory = resolved
        } else {
            return nil
        }

        let headURL = gitDirectory.appendingPathComponent("HEAD", isDirectory: false)
        return fileManager.fileExists(atPath: headURL.path) ? headURL : nil
    }

    /// Parses `gitdir: <path>` from a `.git` pointer file, resolving a relative target
    /// against the repository directory.
    private func linkedGitDirectory(fromPointerFileAt pointer: URL, repository: URL) -> URL? {
        guard let contents = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        let marker = "gitdir:"
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker) else { continue }
            let target = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return nil }
            if target.hasPrefix("/") {
                return URL(fileURLWithPath: target).standardizedFileURL
            }
            return repository.appendingPathComponent(target).standardizedFileURL
        }
        return nil
    }

    // MARK: - HEAD parsing

    /// The branch a `HEAD` file names, or `nil` when it can't be resolved. A symbolic
    /// `ref: refs/heads/<branch>` yields `<branch>` (nested names like `feature/x` are
    /// kept whole); a detached HEAD (a raw commit SHA) yields a short SHA.
    private func branch(fromHeadAt headURL: URL) -> String? {
        guard let raw = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let head = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return nil }

        let branchPrefix = "ref: refs/heads/"
        if head.hasPrefix(branchPrefix) {
            let name = String(head.dropFirst(branchPrefix.count))
            return name.isEmpty ? nil : name
        }
        // A symbolic ref that isn't a local branch (a tag or remote ref): best-effort label.
        let refPrefix = "ref: "
        if head.hasPrefix(refPrefix) {
            let name = head.dropFirst(refPrefix.count).split(separator: "/").last.map(String.init) ?? ""
            return name.isEmpty ? nil : name
        }
        // Detached HEAD: a raw commit SHA. Show a short SHA, never a fabricated branch.
        if isHexSHA(head) {
            return String(head.prefix(7))
        }
        return nil
    }

    private func isHexSHA(_ value: String) -> Bool {
        value.count >= 7 && value.allSatisfy(\.isHexDigit)
    }

    private func modificationDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }
}
