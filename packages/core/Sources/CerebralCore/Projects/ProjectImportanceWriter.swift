import Foundation
import CerebralShared

/// Writes a project's `importance` back into its `PROJECT.md` frontmatter (NIC-129) — the
/// editable priority stepper in the detail window.
///
/// Portable and deterministic (Foundation only). The edit is **surgical**: it replaces the
/// value of an existing `importance:` line, inserts one when the frontmatter block has none, or
/// prepends a fresh block when the file has no frontmatter — every other line (other keys,
/// comments, the body) is preserved byte-for-byte. Like ``ProjectDescriptor``, the file write
/// is constrained to the projects root.
public enum ProjectImportanceWriter {
    /// Returns `contents` with the frontmatter `importance` set to `importance`. Pure: no IO.
    ///
    /// The surgical edit itself lives in ``MarkdownFrontmatter/setting(_:key:value:)``, beside the
    /// parser that has to read it back — two copies of that algorithm would drift, and its edge
    /// cases (no block, unterminated block, key absent) are exactly where drift hides.
    public static func apply(to contents: String, importance: Int) -> String {
        MarkdownFrontmatter.setting(
            contents,
            key: FileSystemActiveProjectsProvider.importanceKey,
            value: String(importance)
        )
    }

    /// Reads `<projectPath>/PROJECT.md`, sets its `importance` (floored at 0), and writes it
    /// back. Returns `false` when the path is outside `root` or the file can't be read/written.
    @discardableResult
    public static func write(
        projectPath: String,
        importance: Int,
        root: URL = WorkspacePaths.defaultProjectsRoot()
    ) -> Bool {
        let folder = URL(fileURLWithPath: projectPath).standardizedFileURL

        // Constrain to the projects root — the same safety invariant as reading.
        let rootPath = root.standardizedFileURL.path
        guard folder.path == rootPath || folder.path.hasPrefix(rootPath + "/") else { return false }

        let descriptor = folder.appendingPathComponent(
            FileSystemActiveProjectsProvider.descriptorFilename, isDirectory: false
        )
        guard let contents = try? String(contentsOf: descriptor, encoding: .utf8) else { return false }

        let updated = apply(to: contents, importance: max(0, importance))
        do {
            try updated.write(to: descriptor, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
