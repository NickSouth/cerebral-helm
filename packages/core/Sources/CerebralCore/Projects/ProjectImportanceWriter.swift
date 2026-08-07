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
    public static func apply(to contents: String, importance: Int) -> String {
        let importanceLine = "\(FileSystemActiveProjectsProvider.importanceKey): \(importance)"
        let lines = contents.components(separatedBy: "\n")

        // No frontmatter block (or an unterminated one): prepend a real block, keep the body.
        guard lines.first == "---" else {
            return "---\n\(importanceLine)\n---\n\n" + contents
        }

        var closeIndex: Int?
        var importanceIndex: Int?
        var index = 1
        while index < lines.count {
            if lines[index] == "---" { closeIndex = index; break }
            if importanceIndex == nil, let colon = lines[index].firstIndex(of: ":") {
                let key = String(lines[index][..<colon]).trimmingCharacters(in: .whitespaces)
                if key == FileSystemActiveProjectsProvider.importanceKey { importanceIndex = index }
            }
            index += 1
        }

        guard closeIndex != nil else {
            // Unterminated frontmatter is not a real block — prepend one.
            return "---\n\(importanceLine)\n---\n\n" + contents
        }

        var updated = lines
        if let importanceIndex {
            updated[importanceIndex] = importanceLine
        } else {
            // Insert as the first frontmatter line, right after the opening fence.
            updated.insert(importanceLine, at: 1)
        }
        return updated.joined(separator: "\n")
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
