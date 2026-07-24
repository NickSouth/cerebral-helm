import Foundation
import CerebralShared

/// Reads a project's `PROJECT.md` descriptor for the expandable detail window (NIC-129).
///
/// Portable and deterministic (Foundation only): the native detail window (Increment 5) calls
/// this to obtain the markdown body it renders. It applies the same safety invariant as
/// `project.open` — the path is constrained to the projects root, so whatever the caller
/// passes, a descriptor outside the root is never read.
public enum ProjectDescriptor {
    /// The rendered content of a project's descriptor: its display name (the project folder
    /// name), the markdown body with any YAML frontmatter stripped, and the current
    /// `importance` value (nil when the descriptor declares none) — the detail window shows it
    /// in an editable stepper.
    public struct Content: Equatable, Sendable {
        public let name: String
        public let body: String
        public let importance: Int?

        public init(name: String, body: String, importance: Int?) {
            self.name = name
            self.body = body
            self.importance = importance
        }
    }

    /// Reads `<projectPath>/PROJECT.md`, returning its name, frontmatter-stripped body, and
    /// `importance`, or `nil` when the path is outside `root` or has no readable descriptor.
    /// The detail window only opens for a project that has a descriptor (Increment 6 gates the
    /// row), so `nil` means "don't open" rather than "open something empty".
    public static func read(
        projectPath: String,
        root: URL = WorkspacePaths.defaultProjectsRoot()
    ) -> Content? {
        let folder = URL(fileURLWithPath: projectPath).standardizedFileURL

        // Constrain to the projects root — the tool-parity safety invariant.
        let rootPath = root.standardizedFileURL.path
        guard folder.path == rootPath || folder.path.hasPrefix(rootPath + "/") else { return nil }

        let descriptor = folder.appendingPathComponent(
            FileSystemActiveProjectsProvider.descriptorFilename, isDirectory: false
        )
        guard let contents = try? String(contentsOf: descriptor, encoding: .utf8) else { return nil }
        let (frontmatter, body) = MarkdownFrontmatter.parse(contents)
        let importance = frontmatter[FileSystemActiveProjectsProvider.importanceKey]
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return Content(name: folder.lastPathComponent, body: body, importance: importance)
    }
}
