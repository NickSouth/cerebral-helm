import Foundation

/// A repository's GitHub remote, resolved from its `origin` URL (NIC-130). Only GitHub remotes
/// are represented — a repository whose `origin` points elsewhere (or has none) resolves to `nil`,
/// and the widget then shows local git state only.
public struct GitRemote: Equatable, Sendable {
    /// The GitHub owner (user or organization), e.g. `NickSouth`.
    public let owner: String
    /// The repository name, with any trailing `.git` stripped, e.g. `cerebral-helm`.
    public let repo: String

    public init(owner: String, repo: String) {
        self.owner = owner
        self.repo = repo
    }
}

/// Resolves a repository's GitHub `owner/repo` from its `origin` remote in `.git/config` (NIC-130).
/// Portable and deterministic: it reads local git files directly and never spawns a process — the
/// same stance as ``FileSystemActiveReposProvider``. A missing `origin`, an unreadable config, or a
/// non-GitHub remote is an honest *absence* (`nil`), not an error, so a repo without a GitHub remote
/// degrades to local-only rather than failing the widget.
///
/// The upstream comparison in ``GitSyncReader`` assumes `origin/<branch>`; this resolver likewise
/// reads the `origin` remote specifically, matching that convention.
public struct GitRemoteResolver: Sendable {
    public init() {}

    /// The GitHub remote for the repository at `repository`, or `nil` when there is no `origin`
    /// remote, the config can't be read, or `origin` is not a GitHub URL.
    public func resolve(forRepositoryAt repository: URL) -> GitRemote? {
        guard let gitDirectory = GitDirectory.locate(forRepositoryAt: repository) else { return nil }
        let configURL = gitDirectory.appendingPathComponent("config", isDirectory: false)
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        guard let url = Self.originURL(inConfig: contents) else { return nil }
        return Self.gitHubRemote(fromRemoteURL: url)
    }

    // MARK: - Parsing (internal for @testable unit tests)

    /// The `url` value from the `[remote "origin"]` section of a git config, or `nil` when the
    /// section or key is absent. Tolerant of whitespace and `#`/`;` comments; stops the origin
    /// section at the next `[…]` header.
    static func originURL(inConfig config: String) -> String? {
        var inOriginSection = false
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                // A section header. The section name is case-insensitive and the quoted subsection
                // is case-sensitive, but `origin` is lowercase by convention; comparing the
                // whitespace-stripped, lowercased body handles `[remote "origin"]` spacing variants.
                let body = line.dropFirst().dropLast()
                let normalized = body.replacingOccurrences(of: " ", with: "").lowercased()
                inOriginSection = normalized == "remote\"origin\""
                continue
            }

            guard inOriginSection, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// The GitHub `owner/repo` a remote URL names, or `nil` when the host isn't GitHub or the URL
    /// can't be parsed. Handles the HTTPS/SSH-URL form (`https://github.com/o/r.git`,
    /// `ssh://git@github.com/o/r.git`) and the scp-like form (`git@github.com:o/r.git`), with or
    /// without a trailing `.git`, and tolerates userinfo/port in the authority.
    static func gitHubRemote(fromRemoteURL url: String) -> GitRemote? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        let path: String
        if let schemeRange = trimmed.range(of: "://") {
            // scheme://[userinfo@]host[:port]/owner/repo(.git)
            let afterScheme = trimmed[schemeRange.upperBound...]
            guard let slash = afterScheme.firstIndex(of: "/") else { return nil }
            var authority = afterScheme[..<slash]
            path = String(afterScheme[afterScheme.index(after: slash)...])
            if let at = authority.lastIndex(of: "@") {
                authority = authority[authority.index(after: at)...]
            }
            host = authority.split(separator: ":").first.map(String.init) ?? String(authority)
        } else if let at = trimmed.lastIndex(of: "@") {
            // scp-like: [userinfo@]host:owner/repo(.git)
            let afterAt = trimmed[trimmed.index(after: at)...]
            guard let colon = afterAt.firstIndex(of: ":") else { return nil }
            host = String(afterAt[..<colon])
            path = String(afterAt[afterAt.index(after: colon)...])
        } else {
            return nil
        }

        let normalizedHost = host.lowercased()
        guard normalizedHost == "github.com" || normalizedHost == "www.github.com" else { return nil }

        // Take the first two non-empty path segments; drop a trailing `.git` from the repo only.
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segments.count >= 2 else { return nil }
        let owner = segments[0]
        var repo = segments[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return GitRemote(owner: owner, repo: repo)
    }
}

/// Locates a repository's git directory — a normal `.git` directory, or the target named by a
/// `.git` *pointer file* (linked worktrees and submodules). Portable; reads files only, never a
/// process. Shared by ``GitRemoteResolver`` and ``GitSyncReader`` (NIC-130).
enum GitDirectory {
    static func locate(forRepositoryAt repository: URL) -> URL? {
        let fileManager = FileManager.default
        let gitPath = repository.appendingPathComponent(".git", isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitPath.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return gitPath }
        return linkedGitDirectory(fromPointerFileAt: gitPath, repository: repository)
    }

    /// Parses `gitdir: <path>` from a `.git` pointer file, resolving a relative target against the
    /// repository directory (mirrors ``FileSystemActiveReposProvider``'s handling).
    private static func linkedGitDirectory(fromPointerFileAt pointer: URL, repository: URL) -> URL? {
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
}
