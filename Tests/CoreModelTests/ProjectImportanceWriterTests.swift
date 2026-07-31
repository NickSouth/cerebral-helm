import Foundation
import Testing

import CerebralCore

/// NIC-129 (priority stepper): writing `importance` back into PROJECT.md frontmatter — a
/// surgical edit that preserves every other line (keys, comments, body).

@Test("replaces the value of an existing importance line, preserving everything else")
func replacesExistingImportance() {
    let source = "---\ntitle: \"Helm\"\nimportance: 5\n---\n# Helm\n\nBody stays.\n"
    let updated = ProjectImportanceWriter.apply(to: source, importance: 9)
    #expect(updated == "---\ntitle: \"Helm\"\nimportance: 9\n---\n# Helm\n\nBody stays.\n")
}

@Test("inserts an importance line when the frontmatter block has none")
func insertsMissingImportance() {
    let source = "---\ntitle: \"Helm\"\n---\nBody.\n"
    let updated = ProjectImportanceWriter.apply(to: source, importance: 4)
    #expect(updated == "---\nimportance: 4\ntitle: \"Helm\"\n---\nBody.\n")
}

@Test("prepends a frontmatter block when the file has none")
func prependsBlockWhenNoFrontmatter() {
    let source = "# Plain\n\nJust prose.\n"
    let updated = ProjectImportanceWriter.apply(to: source, importance: 3)
    #expect(updated == "---\nimportance: 3\n---\n\n# Plain\n\nJust prose.\n")
}

@Test("an unterminated frontmatter block is replaced with a real prepended block")
func prependsWhenUnterminated() {
    let source = "---\nimportance: 1\nno closing fence"
    let updated = ProjectImportanceWriter.apply(to: source, importance: 7)
    #expect(updated == "---\nimportance: 7\n---\n\n---\nimportance: 1\nno closing fence")
}

@Test("round-trips through the reader — the written value parses back")
func roundTripsThroughParse() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("importance-writer-\(UUID().uuidString)", isDirectory: true)
    let folder = root.appendingPathComponent("Proj", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try "---\nimportance: 5\n---\n# Proj\n\nBody.\n".write(
        to: folder.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8
    )

    #expect(ProjectImportanceWriter.write(projectPath: folder.path, importance: 12, root: root))
    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root)?.importance == 12)

    // A path outside the root is refused.
    let outside = root.appendingPathComponent("../Elsewhere/Proj", isDirectory: true)
    #expect(ProjectImportanceWriter.write(projectPath: outside.path, importance: 3, root: root) == false)
}
