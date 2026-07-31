import Foundation
import Testing

import CerebralCore

/// NIC-129 Increment 1: a deterministic reader that lists the project folders under a projects
/// root (`~/Projects/<project>/`), ordered most-important first via each project's `PROJECT.md`
/// `importance` frontmatter, falling back to recency. Depth 1 — the project folder is the unit
/// (contrast the repos reader, which walks one level deeper to the git repositories).

private func temporaryProjectsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("active-projects-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Creates a project folder `root/<name>`. When `descriptor` is non-nil it writes a
/// `PROJECT.md` with that content. `modifiedAt` stamps the folder's mtime (the recency
/// signal) — set last, since writing the descriptor would otherwise bump it.
@discardableResult
private func makeProject(
    in root: URL,
    name: String,
    descriptor: String? = nil,
    modifiedAt: Date? = nil
) throws -> URL {
    let fileManager = FileManager.default
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    if let descriptor {
        try descriptor.write(
            to: folder.appendingPathComponent("PROJECT.md"), atomically: true, encoding: .utf8
        )
    }
    if let modifiedAt {
        try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: folder.path)
    }
    return folder
}

private func descriptor(importance: Int) -> String {
    "---\nimportance: \(importance)\n---\n# Project\n\nBody.\n"
}

@Test("lists each project folder at depth 1 by name")
func listsProjectFolders() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "CerebralHelm")
    try makeProject(in: root, name: "OnDraft")

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(Set(projects.map(\.name)) == ["CerebralHelm", "OnDraft"])
    let helm = projects.first { $0.name == "CerebralHelm" }
    #expect(helm?.id == "CerebralHelm")
    #expect(helm?.path.hasSuffix("/CerebralHelm") == true)
}

@Test("a project without a PROJECT.md has no descriptor and no importance")
func projectWithoutDescriptor() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "Undocumented")

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(projects.count == 1)
    #expect(projects[0].hasDescriptor == false)
    #expect(projects[0].descriptorPath == nil)
    #expect(projects[0].importance == nil)
}

@Test("a PROJECT.md descriptor is detected and its importance parsed")
func projectWithDescriptor() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "Documented", descriptor: descriptor(importance: 7))

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(projects.count == 1)
    #expect(projects[0].hasDescriptor == true)
    #expect(projects[0].descriptorPath?.hasSuffix("/Documented/PROJECT.md") == true)
    #expect(projects[0].importance == 7)
}

@Test("a descriptor without an importance field parses to a nil importance")
func descriptorWithoutImportance() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "NoImportance", descriptor: "---\ntitle: \"X\"\n---\nBody.\n")

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(projects[0].hasDescriptor == true)
    #expect(projects[0].importance == nil)
}

@Test("projects are ordered by importance descending, then by recency for the undecorated")
func ordersByImportanceThenRecency() throws {
    let root = try temporaryProjectsRoot()
    // Decorated projects — importance dominates regardless of mtime.
    try makeProject(in: root, name: "high", descriptor: descriptor(importance: 10))
    try makeProject(in: root, name: "low", descriptor: descriptor(importance: 2))
    // Undecorated projects — ordered by folder mtime, newer first.
    try makeProject(in: root, name: "older-plain", modifiedAt: Date(timeIntervalSince1970: 1_000))
    try makeProject(in: root, name: "newer-plain", modifiedAt: Date(timeIntervalSince1970: 2_000))

    let ordered = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(ordered.map(\.name) == ["high", "low", "newer-plain", "older-plain"])
}

@Test("projects are capped by the limit, keeping the most important")
func capsByLimit() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "a", descriptor: descriptor(importance: 1))
    try makeProject(in: root, name: "b", descriptor: descriptor(importance: 5))
    try makeProject(in: root, name: "c", descriptor: descriptor(importance: 3))

    let capped = try FileSystemActiveProjectsProvider(root: root, limit: 2).activeProjects()
    #expect(capped.map(\.name) == ["b", "c"]) // importance 5, 3 — the top two
}

@Test("loose files under the root are ignored; only directories are projects")
func ignoresLooseFiles() throws {
    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "real")
    try "notes".write(to: root.appendingPathComponent("loose.txt"), atomically: true, encoding: .utf8)

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(projects.map(\.name) == ["real"])
}

@Test("a readable but project-less root returns empty; a missing root is unavailable")
func distinguishesEmptyProjectsFromUnavailable() throws {
    let emptyRoot = try temporaryProjectsRoot()
    #expect(try FileSystemActiveProjectsProvider(root: emptyRoot).activeProjects().isEmpty)

    let missing = emptyRoot.appendingPathComponent("does-not-exist", isDirectory: true)
    #expect(throws: ActiveProjectsError.rootUnavailable(missing.path)) {
        _ = try FileSystemActiveProjectsProvider(root: missing).activeProjects()
    }
}

@Test("the shipped PROJECT.md template is a valid descriptor the reader parses")
func shippedTemplateParses() throws {
    // The bundled scaffold a future 'make project' quick action will copy (config/templates).
    // Locking the template and the parser to the same contract: if either drifts, this fails.
    let templateURL = repositoryRoot().appendingPathComponent("config/templates/PROJECT.md")
    let template = try String(contentsOf: templateURL, encoding: .utf8)

    let root = try temporaryProjectsRoot()
    try makeProject(in: root, name: "FromTemplate", descriptor: template)

    let projects = try FileSystemActiveProjectsProvider(root: root).activeProjects()
    #expect(projects.count == 1)
    #expect(projects[0].hasDescriptor == true)
    #expect(projects[0].importance == 5) // the template's starter importance
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}
