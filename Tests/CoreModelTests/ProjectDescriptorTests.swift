import Foundation
import Testing

import CerebralCore

/// NIC-129 Increment 5: reading a project's PROJECT.md for the detail window — name + the
/// frontmatter-stripped markdown body, constrained to the projects root.

private func temporaryProjectsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("project-descriptor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@discardableResult
private func makeProject(in root: URL, name: String, descriptor: String?) throws -> URL {
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let descriptor {
        try descriptor.write(to: folder.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8)
    }
    return folder
}

@Test("reads the project name and the frontmatter-stripped markdown body")
func readsNameAndBody() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "CerebralHelm",
        descriptor: "---\nimportance: 10\n---\n# CerebralHelm\n\nLocal-first desktop.\n"
    )

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.name == "CerebralHelm")
    #expect(content?.body == "# CerebralHelm\n\nLocal-first desktop.\n")
    #expect(content?.importance == 10)
    // The frontmatter block is stripped from the rendered body.
    #expect(content?.body.contains("importance") == false)
}

@Test("a project with no PROJECT.md yields nil, never an empty body")
func missingDescriptorIsNil() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(in: root, name: "Undocumented", descriptor: nil)
    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root) == nil)
}

@Test("a path outside the projects root is refused, even if a PROJECT.md exists there")
func refusesPathOutsideRoot() throws {
    let root = try temporaryProjectsRoot()
    let outside = try temporaryProjectsRoot() // a sibling root, not under `root`
    let folder = try makeProject(in: outside, name: "Elsewhere", descriptor: "---\n---\nBody.\n")

    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root) == nil)
}

// MARK: - The Linear link (NIC-221)

@Test("reads the linked Linear project from frontmatter")
func readsLinearProject() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "CerebralHelm",
        descriptor: "---\nimportance: 10\nlinear_project: CerebralHelm\n---\n# CerebralHelm\n"
    )

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.linearProject == "CerebralHelm")
    // The key is frontmatter, so it never reaches the rendered body.
    #expect(content?.body.contains("linear_project") == false)
}

@Test("a project name with spaces survives, and the value is trimmed")
func readsLinearProjectWithSpaces() throws {
    // "Ubility Website" is a real project name — an unquoted value containing spaces has to
    // arrive whole, and trailing whitespace must not become part of the lookup name.
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "Ubility",
        descriptor: "---\nlinear_project:   Ubility Website  \n---\nBody.\n"
    )

    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root)?.linearProject == "Ubility Website")
}

@Test("a quoted project name is unquoted, matching the frontmatter grammar")
func readsQuotedLinearProject() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "Quoted",
        descriptor: "---\nlinear_project: \"Personal Tasks\"\n---\nBody.\n"
    )

    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root)?.linearProject == "Personal Tasks")
}

@Test("a descriptor with no linear_project is unlinked, not empty-named")
func absentLinearProjectIsNil() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "Unlinked", descriptor: "---\nimportance: 3\n---\nBody.\n"
    )

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.linearProject == nil)
    // The rest of the descriptor still reads normally — the key is optional, not required.
    #expect(content?.importance == 3)
}

@Test("a declared-but-blank linear_project reads as unlinked")
func blankLinearProjectIsNil() throws {
    // Otherwise the empty string would reach the API as a genuine lookup for a project named "".
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(
        in: root, name: "Blank", descriptor: "---\nlinear_project:   \n---\nBody.\n"
    )

    #expect(ProjectDescriptor.read(projectPath: folder.path, root: root)?.linearProject == nil)
}

@Test("a descriptor with no frontmatter returns the whole file as the body")
func noFrontmatterReturnsWholeBody() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(in: root, name: "Plain", descriptor: "# Plain\n\nJust prose.\n")

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.body == "# Plain\n\nJust prose.\n")
}
