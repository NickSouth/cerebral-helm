import Foundation
import Testing

import CerebralCore
import CerebralShared

/// NIC-221 Increment 6: writing `linear_project` back into PROJECT.md frontmatter from the detail
/// window's picker.
///
/// This writes a file the user hand-authors, so most of these tests are about what must NOT
/// change. The rest are about quoting: an importance is always a safe scalar, a project name is
/// arbitrary text, and a value the writer emits must be the value the reader reads back.

@Test("sets the key while preserving every other line")
func linearLinkPreservesOtherLines() {
    let source = "---\nimportance: 10\nlinear_project: Old Name\n---\n# Helm\n\nBody stays.\n"
    let updated = ProjectLinearLinkWriter.apply(to: source, linearProject: "CerebralHelm")
    #expect(updated == "---\nimportance: 10\nlinear_project: CerebralHelm\n---\n# Helm\n\nBody stays.\n")
}

@Test("inserts the key when the frontmatter has only importance")
func linearLinkInsertsKey() {
    // The shape every existing descriptor is in today — importance and nothing else.
    let source = "---\nimportance: 5\n---\nBody.\n"
    let updated = ProjectLinearLinkWriter.apply(to: source, linearProject: "Ubility Website")
    #expect(updated == "---\nlinear_project: Ubility Website\nimportance: 5\n---\nBody.\n")
}

@Test("prepends a block when the descriptor has no frontmatter")
func linearLinkPrependsBlock() {
    let source = "# Plain\n\nJust prose.\n"
    let updated = ProjectLinearLinkWriter.apply(to: source, linearProject: "CerebralHelm")
    #expect(updated == "---\nlinear_project: CerebralHelm\n---\n\n# Plain\n\nJust prose.\n")
}

@Test("an unterminated block is treated as body, not edited in place")
func linearLinkPrependsWhenUnterminated() {
    let source = "---\nimportance: 1\nno closing fence"
    let updated = ProjectLinearLinkWriter.apply(to: source, linearProject: "Helm")
    #expect(updated == "---\nlinear_project: Helm\n---\n\n---\nimportance: 1\nno closing fence")
}

// MARK: - Quoting

@Test("a plain name is written unquoted — the descriptor stays pleasant to hand-edit")
func linearLinkWritesPlainNameUnquoted() {
    #expect(MarkdownFrontmatter.scalar("CerebralHelm") == "CerebralHelm")
    #expect(MarkdownFrontmatter.scalar("Ubility Website") == "Ubility Website")
}

@Test("a name containing a colon needs no quoting and round-trips")
func linearLinkColonNameRoundTrips() {
    // The parser splits on the FIRST colon, so everything after it is the value.
    let written = ProjectLinearLinkWriter.apply(to: "---\n---\nBody.\n", linearProject: "Q3: Launch")
    let (frontmatter, _) = MarkdownFrontmatter.parse(written)
    #expect(frontmatter["linear_project"] == "Q3: Launch")
}

@Test("a name already wrapped in quotes is escaped, or the reader would strip them")
func linearLinkQuotedNameIsEscaped() {
    // Written bare, `"Helm"` would be UNQUOTED on read and come back as `Helm` — a different
    // project. The round trip is the assertion that matters, not the exact bytes.
    let written = ProjectLinearLinkWriter.apply(to: "---\n---\nBody.\n", linearProject: "\"Helm\"")
    let (frontmatter, _) = MarkdownFrontmatter.parse(written)
    #expect(frontmatter["linear_project"] == "\"Helm\"")
}

@Test("a name carrying a newline cannot break out of the frontmatter block")
func linearLinkNewlineIsContained() {
    let written = ProjectLinearLinkWriter.apply(
        to: "---\nimportance: 2\n---\nBody.\n", linearProject: "Helm\n---\nevil: true"
    )
    let (frontmatter, body) = MarkdownFrontmatter.parse(written)
    // The injected key never becomes frontmatter, and the body is still the body.
    #expect(frontmatter["evil"] == nil)
    #expect(frontmatter["importance"] == "2")
    #expect(body == "Body.\n")
}

// MARK: - Writing to disk

private func linearLinkTemporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("linear-link-writer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@discardableResult
private func linearLinkMakeProject(in root: URL, name: String, descriptor: String) throws -> URL {
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try descriptor.write(
        to: folder.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8
    )
    return folder
}

@Test("the written link is what the descriptor reader reads back")
func linearLinkRoundTripsThroughReader() throws {
    let root = try linearLinkTemporaryRoot()
    let folder = try linearLinkMakeProject(
        in: root, name: "CerebralHelm", descriptor: "---\nimportance: 10\n---\n# Helm\n\nBody.\n"
    )

    #expect(ProjectLinearLinkWriter.write(
        projectPath: folder.path, linearProject: "CerebralHelm", root: root
    ))

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.linearProject == "CerebralHelm")
    // The rest of the descriptor is untouched — importance survives, and so does the body.
    #expect(content?.importance == 10)
    #expect(content?.body == "# Helm\n\nBody.\n")
}

@Test("a path outside the projects root is refused and nothing is written")
func linearLinkRefusesPathOutsideRoot() throws {
    let root = try linearLinkTemporaryRoot()
    let outside = try linearLinkTemporaryRoot()
    let original = "---\nimportance: 1\n---\nBody.\n"
    let folder = try linearLinkMakeProject(in: outside, name: "Elsewhere", descriptor: original)

    #expect(ProjectLinearLinkWriter.write(
        projectPath: folder.path, linearProject: "Helm", root: root
    ) == false)
    // Refused means untouched, not partially written.
    let after = try String(
        contentsOf: folder.appendingPathComponent("PROJECT.md"), encoding: .utf8
    )
    #expect(after == original)
}

@Test("a blank name is refused rather than written as an empty link")
func linearLinkRefusesBlankName() throws {
    // `linear_project:` with nothing after it reads back as UNLINKED, so writing one would report
    // success while changing nothing the user asked for.
    let root = try linearLinkTemporaryRoot()
    let folder = try linearLinkMakeProject(in: root, name: "Helm", descriptor: "---\nimportance: 1\n---\nB.\n")
    #expect(ProjectLinearLinkWriter.write(projectPath: folder.path, linearProject: "  ", root: root) == false)
    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root)?.linearProject == nil)
}

@Test("a project with no descriptor is refused — the writer never creates one")
func linearLinkRefusesMissingDescriptor() throws {
    let root = try linearLinkTemporaryRoot()
    let folder = root.appendingPathComponent("NoDescriptor", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(ProjectLinearLinkWriter.write(
        projectPath: folder.path, linearProject: "Helm", root: root
    ) == false)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("PROJECT.md").path) == false)
}
