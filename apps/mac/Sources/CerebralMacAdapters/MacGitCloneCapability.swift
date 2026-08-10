// Repository clone (quick-actions phase 4) — the `git-clone` quick action's actuator.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Clones a repository into a folder under the projects root by exec'ing a **fixed** `git`
/// binary with a typed argument list.
///
/// It composes over ``ProcessCapability`` rather than re-implementing process management: that
/// adapter already guarantees the properties that matter here — an exactly-specified environment,
/// every inherited file descriptor closed, a dedicated process group so a timeout kills the whole
/// tree, drained output, and no blocked cooperative-pool thread. What it does *not* reuse is the
/// `hook.run` tool: a hook is free-form configured shell, which is why it is `shell`-class and
/// confirms every run. Here the executable is a constant and the caller supplies no program, so
/// the operation is honestly `local_write`.
///
/// Three invariants live here, not in the caller:
///
/// 1. **Scheme.** Only `https` is accepted. `file://`, `ssh://` and git's scp-like `host:path`
///    form are refused — the first would make "clone" a local copy tool with a caller-chosen
///    source path, and the others reach for credentials this has no business using.
/// 2. **No embedded credentials.** A URL carrying `user:token@host` is refused rather than
///    redacted: a rejected token never reaches the command log, a redacted one already did.
/// 3. **Containment.** The destination is resolved inside the projects root and re-checked *after*
///    standardizing, so `..` in a supplied folder name cannot place a clone elsewhere. An existing
///    path is a refusal, never an overwrite.
public struct MacGitCloneCapability: GitCloneCapability {
    /// Absolute, so PATH can never decide which binary runs. On macOS this is the Command Line
    /// Tools shim; a machine without them reports an honest `notFound` rather than hanging.
    private static let gitExecutable = "/usr/bin/git"

    private let process: any ProcessCapability
    private let projectsRoot: URL

    public init(
        process: any ProcessCapability = ProcessHookCapability(),
        projectsRoot: URL = WorkspacePaths.defaultProjectsRoot()
    ) {
        self.process = process
        self.projectsRoot = projectsRoot
    }

    public func clone(repositoryURL: String, directory: String?) async throws -> GitCloneResult {
        let source = try Self.validatedSource(repositoryURL)
        let folder = try Self.folderName(directory: directory, repositoryURL: source)
        let target = try Self.resolveTarget(root: projectsRoot, folder: folder)

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: target.path) else {
            throw NativeCapabilityError.adapterFailure(
                "'\(target.lastPathComponent)' already exists in your projects folder. Choose a different folder name."
            )
        }
        guard fileManager.fileExists(atPath: Self.gitExecutable) else {
            throw NativeCapabilityError.notFound(
                "git is not installed at \(Self.gitExecutable). Install the Xcode Command Line Tools with 'xcode-select --install'."
            )
        }
        // The parent may be missing when the folder name nests (`owner/repo`). Creating it up
        // front keeps the failure modes to "git refused" rather than "no such directory".
        let parent = target.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw NativeCapabilityError.adapterFailure(
                "Could not create '\(parent.path)': \(error.localizedDescription)"
            )
        }

        let result = try await process.run(HookInvocation(
            executable: Self.gitExecutable,
            arguments: ["clone", source.absoluteString, target.path],
            workingDirectory: projectsRoot.path,
            // An exactly-specified environment, and deliberately no credential helper: a private
            // repository fails fast with git's own message instead of blocking forever on a prompt
            // no one can see. `PATH` is present only because git re-execs its own subcommands.
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": fileManager.homeDirectoryForCurrentUser.path,
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/usr/bin/true",
                "GIT_CONFIG_NOSYSTEM": "1"
            ]
        ))

        guard result.exitCode == 0 else {
            // A partial checkout left behind by a failed clone would masquerade as a repository in
            // the projects widget, so it goes.
            try? fileManager.removeItem(at: target)
            throw NativeCapabilityError.adapterFailure(Self.failureMessage(from: result))
        }
        return GitCloneResult(clonedPath: target.path, repositoryName: target.lastPathComponent)
    }

    // MARK: - Pure helpers (unit-tested)

    /// Accepts only an `https` URL with a host and no embedded credentials.
    static func validatedSource(_ repositoryURL: String) throws -> URL {
        let trimmed = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Deliberately does not echo the input. A malformed URL can still carry a
        // token (`https://user:tok en@host/...` fails to parse but holds a secret),
        // and this message reaches the same `tool_calls` record the credential guard
        // below exists to keep tokens out of. Describing the expected shape is as
        // useful to the user and cannot leak (NIC-104).
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            throw NativeCapabilityError.adapterFailure(
                "That is not a repository URL. Use a plain https URL, e.g. https://github.com/owner/repo.git"
            )
        }
        guard url.scheme?.lowercased() == "https" else {
            throw NativeCapabilityError.adapterFailure(
                "Only https repository URLs can be cloned — '\(url.scheme ?? "no scheme")' is refused."
            )
        }
        guard url.user == nil, url.password == nil else {
            throw NativeCapabilityError.adapterFailure(
                "That URL carries credentials. Use the plain https URL; the token would end up in the command log."
            )
        }
        return url
    }

    /// The folder the clone lands in: the supplied name, else the repository name with any `.git`
    /// suffix removed. Rejects an absolute path and a leading `..` outright — containment is
    /// re-checked afterwards regardless, but a clear refusal beats a confusing one.
    static func folderName(directory: String?, repositoryURL: URL) throws -> String {
        if let directory {
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
                    throw NativeCapabilityError.permissionDenied
                }
                return trimmed
            }
        }
        var derived = repositoryURL.lastPathComponent
        if derived.hasSuffix(".git") { derived.removeLast(4) }
        guard !derived.isEmpty, derived != "/" else {
            throw NativeCapabilityError.adapterFailure(
                "Could not work out a folder name from that URL. Give the clone a folder name."
            )
        }
        return derived
    }

    /// Resolves `folder` inside `root` and re-checks containment after standardizing, so a `..`
    /// segment can never escape. The root itself is not a valid destination.
    static func resolveTarget(root: URL, folder: String) throws -> URL {
        let rootPath = root.standardizedFileURL.path
        let target = root.appendingPathComponent(folder).standardizedFileURL
        guard target.path.hasPrefix(rootPath + "/"), target.path != rootPath else {
            throw NativeCapabilityError.permissionDenied
        }
        return target
    }

    /// git reports its reason on stderr; the exit code alone tells the user nothing.
    static func failureMessage(from result: ProcessRunResult) -> String {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "git clone failed (exit code \(result.exitCode))."
        }
        return "git clone failed: \(detail)"
    }
}
#endif
