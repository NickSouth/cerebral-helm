// Quick actions phase 4: scaffolding a project folder.
//
// The safety invariants are pure functions tested directly; the write path runs against a real
// temporary directory. Gated so Linux CI compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore
import CerebralShared
import CerebralTools

private let root = URL(fileURLWithPath: "/Users/example/Projects", isDirectory: true)

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MacAdapterTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

// MARK: - Naming

@Test("a name containing a path separator is REFUSED, not sanitized")
func projectNameRefusesSeparators() throws {
    // Silently turning "Helm / v2" into a nested folder would put the project somewhere the user
    // never asked for. A name they can see is wrong beats a path they cannot.
    for refused in ["Helm / v2", "a:b", ".hidden", "   "] {
        #expect(throws: NativeCapabilityError.self) {
            _ = try ProjectScaffolder.folderName(from: refused)
        }
    }
    #expect(try ProjectScaffolder.folderName(from: "  Helm Companion  ") == "Helm Companion")
}

// MARK: - Containment

@Test("the project resolves inside the projects root, under an optional location")
func projectResolvesInsideRoot() throws {
    #expect(
        try ProjectScaffolder.resolveTarget(root: root, location: nil, folder: "Helm").path
            == "/Users/example/Projects/Helm"
    )
    #expect(
        try ProjectScaffolder.resolveTarget(root: root, location: "CerebralHelm", folder: "Helm").path
            == "/Users/example/Projects/CerebralHelm/Helm"
    )
    // A blank location is the same as none.
    #expect(
        try ProjectScaffolder.resolveTarget(root: root, location: "  ", folder: "Helm").path
            == "/Users/example/Projects/Helm"
    )
}

@Test("a relative escape in the location cannot place a project outside the root")
func projectRefusesEscape() {
    for escape in ["..", "../Desktop", "a/../..", "/tmp", "~"] {
        #expect(throws: NativeCapabilityError.self) {
            _ = try ProjectScaffolder.resolveTarget(root: root, location: escape, folder: "Helm")
        }
    }
}

// MARK: - Descriptor

@Test("the descriptor carries the name, the summary and a parseable importance")
func projectDescriptorContents() throws {
    let contents = ProjectScaffolder.descriptorContents(
        name: "Helm Companion", summary: "A companion surface.", importance: 7
    )
    #expect(contents.hasPrefix("---\nimportance: 7\n---"))
    #expect(contents.contains("# Helm Companion"))
    #expect(contents.contains("_A companion surface._"))

    // The importance is what orders the Projects widget, so it must survive the same parser the
    // reader uses — not merely look right.
    let (frontmatter, _) = MarkdownFrontmatter.parse(contents)
    #expect(frontmatter[FileSystemActiveProjectsProvider.importanceKey] == "7")
}

@Test("a blank summary and importance fall back rather than writing empties")
func projectDescriptorDefaults() {
    let contents = ProjectScaffolder.descriptorContents(name: "Helm", summary: "  ", importance: nil)
    #expect(contents.contains("importance: \(ProjectScaffolder.defaultImportance)"))
    #expect(contents.contains("_One-line summary"))
}

@Test("the generated descriptor keeps the shipped template's shape")
func projectDescriptorMatchesTemplate() throws {
    // Composed in code rather than substituted into the template — so this is the check that the
    // two do not drift apart. It compares structure, which survives edits to either's prose.
    let template = try String(
        contentsOf: repoRoot().appendingPathComponent("config/templates/PROJECT.md"), encoding: .utf8
    )
    let generated = ProjectScaffolder.descriptorContents(name: "X", summary: nil, importance: nil)
    for heading in ["## Focus", "## Notes"] {
        #expect(template.contains(heading), "the template lost \(heading)")
        #expect(generated.contains(heading), "the generated descriptor lost \(heading)")
    }
    #expect(template.contains("importance:"))
    #expect(generated.contains("importance:"))
}

// MARK: - Writing

@Test("scaffolding creates the folder and its descriptor, and refuses an existing name")
func projectScaffoldWrites() async throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ch-project-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let scaffolder = ProjectScaffolder(projectsRoot: temporaryRoot)
    let result = try await scaffolder.scaffold(
        name: "Helm Companion", location: "CerebralHelm", summary: "Companion surface.", importance: 7
    )

    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: result.projectPath, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    #expect(FileManager.default.fileExists(atPath: result.descriptorPath))

    // The reader must actually see it as a project — the whole point of writing a descriptor.
    let projects = try FileSystemActiveProjectsProvider(root: temporaryRoot).activeProjects()
    #expect(projects.contains { $0.name == "CerebralHelm" })

    // A second scaffold with the same name is a refusal, never an overwrite.
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await scaffolder.scaffold(
            name: "Helm Companion", location: "CerebralHelm", summary: nil, importance: nil
        )
    }
}
#endif
