import Foundation
import CerebralShared

/// One project under the user's projects root (NIC-129). A project is an immediate child
/// directory of the root — `~/Projects/<project>/` — that groups a coding project's repo(s)
/// and, by convention, a `PROJECT.md` descriptor. Produced by ``ActiveProjectsProvider`` and
/// mapped to the `projects` widget's payload by its live producer (Increment 3).
public struct ProjectSummary: Equatable, Sendable {
    /// Stable identity within the root: the project directory name.
    public let id: String
    /// Display name: the project directory name.
    public let name: String
    /// Absolute path of the project directory.
    public let path: String
    /// Absolute path of the project's `PROJECT.md` descriptor when one exists, else `nil`.
    /// The click-to-expand detail window (Increment 5) reads this; a `nil` descriptor means
    /// the project row is present but not expandable (Increment 6).
    public let descriptorPath: String?
    /// Whether a `PROJECT.md` descriptor exists — the honest gate for expandability.
    public let hasDescriptor: Bool
    /// The `importance` frontmatter value from the descriptor (higher = more important), or
    /// `nil` when there is no descriptor or it carries no numeric `importance`. Drives the
    /// primary ordering; `nil` sorts after any project that declares one.
    public let importance: Int?
    /// When the project was last active, taken from the mtime of its directory. Breaks ties
    /// among projects with equal (or absent) importance, most-recent first, and is available
    /// for a future freshness label.
    public let lastActivityAt: Date

    public init(
        id: String,
        name: String,
        path: String,
        descriptorPath: String?,
        hasDescriptor: Bool,
        importance: Int?,
        lastActivityAt: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.descriptorPath = descriptorPath
        self.hasDescriptor = hasDescriptor
        self.importance = importance
        self.lastActivityAt = lastActivityAt
    }
}

/// Why the projects root could not be read — distinct from "read fine, no projects".
public enum ActiveProjectsError: Error, Equatable {
    /// The configured projects root does not exist or is not a readable directory. The
    /// producer maps this to an honest "unavailable" widget state, never an empty one.
    case rootUnavailable(String)
}

/// Port that lists the projects under a configured projects root, most-important first
/// (NIC-129). Portable and deterministic: it reads local filesystem state only and never
/// spawns a process. The live producer (Increment 3) samples it; tests bind
/// ``FileSystemActiveProjectsProvider`` against a temp directory.
public protocol ActiveProjectsProvider: Sendable {
    /// The projects under the root, most-important first. Throws
    /// ``ActiveProjectsError/rootUnavailable(_:)`` when the root itself can't be read;
    /// returns an empty array when the root is readable but holds no project folders.
    func activeProjects() throws -> [ProjectSummary]
}

/// Lists projects by reading the immediate child directories of the projects root (NIC-129):
/// each is a **project folder** — `~/Projects/<project>/` — grouping a project's repo(s) and,
/// by convention, a `PROJECT.md` descriptor in the folder itself. Unlike
/// ``FileSystemActiveReposProvider`` (which walks one level deeper to the git repositories),
/// this reader stays at depth 1: the project folder *is* the unit. It parses only the
/// descriptor's `importance` frontmatter (via ``MarkdownFrontmatter``) — never the body — and
/// spawns no process.
///
/// Ordering (owner decision, NIC-129): projects that declare an `importance` rank first, in
/// descending importance; the rest follow by most-recently-modified directory. So a
/// hand-authored `importance` pins the important projects to the top while undecorated
/// projects still surface by recency until the user writes a descriptor. The canonical
/// descriptor shape ships as a template at `config/templates/PROJECT.md`.
public struct FileSystemActiveProjectsProvider: ActiveProjectsProvider {
    /// The canonical descriptor filename a project folder may contain (NIC-129).
    public static let descriptorFilename = "PROJECT.md"
    /// The frontmatter key whose integer value orders the list (higher = more important).
    public static let importanceKey = "importance"
    /// The frontmatter key naming the Linear project this folder tracks, by its human-readable
    /// name (NIC-221) — e.g. `linear_project: CerebralHelm`. A name rather than a UUID because a
    /// descriptor is hand-authored, and an opaque id in a file the user edits is unmaintainable;
    /// the resolution from name to project happens at the API boundary.
    ///
    /// Deliberately **not** read by this reader: the widget's list and its ordering do not depend
    /// on it, so a project without the key is simply unlinked rather than incomplete. Only
    /// ``ProjectDescriptor`` reads it, for the detail window.
    public static let linearProjectKey = "linear_project"

    private let root: URL
    private let limit: Int

    /// - Parameters:
    ///   - root: the projects root to scan (default ``WorkspacePaths/defaultProjectsRoot()``).
    ///   - limit: the maximum number of projects to return (most-important first).
    public init(root: URL = WorkspacePaths.defaultProjectsRoot(), limit: Int = 6) {
        self.root = root
        self.limit = max(0, limit)
    }

    public func activeProjects() throws -> [ProjectSummary] {
        let fileManager = FileManager.default

        var rootIsDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
            rootIsDirectory.boolValue,
            let projectFolders = subdirectories(of: root)
        else {
            throw ActiveProjectsError.rootUnavailable(root.path)
        }

        let projects = projectFolders.map { folder -> ProjectSummary in
            let descriptorURL = folder.appendingPathComponent(Self.descriptorFilename, isDirectory: false)
            let hasDescriptor = fileManager.fileExists(atPath: descriptorURL.path)
            return ProjectSummary(
                id: folder.lastPathComponent,
                name: folder.lastPathComponent,
                path: folder.standardizedFileURL.path,
                descriptorPath: hasDescriptor ? descriptorURL.standardizedFileURL.path : nil,
                hasDescriptor: hasDescriptor,
                importance: hasDescriptor ? importance(fromDescriptorAt: descriptorURL) : nil,
                lastActivityAt: modificationDate(of: folder)
            )
        }

        // Most-important first: a declared importance outranks an absent one and a higher
        // importance wins; among equals (including the undecorated majority) the more
        // recently modified folder wins, with the name as a final deterministic tiebreak.
        let ordered = projects.sorted { lhs, rhs in
            switch (lhs.importance, rhs.importance) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                if lhs.lastActivityAt != rhs.lastActivityAt {
                    return lhs.lastActivityAt > rhs.lastActivityAt
                }
                return lhs.name < rhs.name
            }
        }
        return Array(ordered.prefix(limit))
    }

    // MARK: - Descriptor

    /// Reads the `importance` frontmatter integer from a `PROJECT.md`, or `nil` when the file
    /// is unreadable or carries no numeric `importance`. Only the frontmatter is parsed here —
    /// the body is rendered by the detail window (Increment 4), not by the list.
    private func importance(fromDescriptorAt descriptor: URL) -> Int? {
        guard let contents = try? String(contentsOf: descriptor, encoding: .utf8) else { return nil }
        let (frontmatter, _) = MarkdownFrontmatter.parse(contents)
        guard let raw = frontmatter[Self.importanceKey] else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Filesystem helpers

    /// The immediate subdirectories of `directory` (visible only), or `nil` when it can't be
    /// listed. `nil` on the root is `rootUnavailable`.
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

    private func modificationDate(of url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? .distantPast
    }
}
