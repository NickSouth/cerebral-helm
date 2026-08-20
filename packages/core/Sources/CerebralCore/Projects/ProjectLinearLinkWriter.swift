import Foundation
import CerebralShared

/// Writes a project's `linear_project` into its `PROJECT.md` frontmatter (NIC-221) — the detail
/// window's "link this to Linear" picker.
///
/// Portable and deterministic (Foundation only), and the exact sibling of
/// ``ProjectImportanceWriter``: the same surgical edit through
/// ``MarkdownFrontmatter/setting(_:key:value:)``, the same containment to the projects root.
///
/// This touches a file the user hand-authors, so the invariant that matters is that **nothing
/// else changes** — other keys, comments and the whole body survive byte for byte. The one
/// addition over the importance writer is quoting: an integer is always a safe scalar, a project
/// name is not, so the value goes through ``MarkdownFrontmatter/scalar(_:)`` first.
public enum ProjectLinearLinkWriter {
    /// Returns `contents` with the frontmatter `linear_project` set to `linearProject`, quoted
    /// only if the grammar requires it. Pure: no IO.
    public static func apply(to contents: String, linearProject: String) -> String {
        MarkdownFrontmatter.setting(
            contents,
            key: FileSystemActiveProjectsProvider.linearProjectKey,
            value: MarkdownFrontmatter.scalar(linearProject)
        )
    }

    /// Reads `<projectPath>/PROJECT.md`, sets its `linear_project`, and writes it back. Returns
    /// `false` when the path is outside `root`, the name is blank, or the file can't be
    /// read/written — never a silent partial success.
    ///
    /// A blank name is refused rather than written: `linear_project:` with nothing after it reads
    /// back as *unlinked*, so writing one would report success while leaving the project exactly
    /// as it was. Unlinking is not this writer's job.
    @discardableResult
    public static func write(
        projectPath: String,
        linearProject: String,
        root: URL = WorkspacePaths.defaultProjectsRoot()
    ) -> Bool {
        let name = linearProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        let folder = URL(fileURLWithPath: projectPath).standardizedFileURL

        // Constrain to the projects root — the same safety invariant as reading and as the
        // importance write. Whatever the caller passes, a descriptor outside the root is never
        // touched.
        let rootPath = root.standardizedFileURL.path
        guard folder.path == rootPath || folder.path.hasPrefix(rootPath + "/") else { return false }

        let descriptor = folder.appendingPathComponent(
            FileSystemActiveProjectsProvider.descriptorFilename, isDirectory: false
        )
        guard let contents = try? String(contentsOf: descriptor, encoding: .utf8) else { return false }

        do {
            try apply(to: contents, linearProject: name)
                .write(to: descriptor, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
