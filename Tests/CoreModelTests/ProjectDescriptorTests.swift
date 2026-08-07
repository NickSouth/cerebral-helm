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

@Test("a descriptor with no frontmatter returns the whole file as the body")
func noFrontmatterReturnsWholeBody() throws {
    let root = try temporaryProjectsRoot()
    let folder = try makeProject(in: root, name: "Plain", descriptor: "# Plain\n\nJust prose.\n")

    let content = ProjectDescriptor.read(projectPath: folder.path, root: root)
    #expect(content?.body == "# Plain\n\nJust prose.\n")
}
