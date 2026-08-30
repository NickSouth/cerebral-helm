import Foundation
import Testing
@testable import CerebralCore

/// NIC-228: which project's sprint the brief reports on.
///
/// The rule is one sentence — the highest-`importance` active project that declares a
/// `linear_project` — and it is tested here rather than at the app edge because that is a rule, and
/// a rule living in `apps/mac` would be covered by no CI job at all.

private func project(_ name: String, importance: Int?, hasDescriptor: Bool = true) -> ProjectSummary {
    ProjectSummary(
        id: name,
        name: name,
        path: "/projects/\(name)",
        descriptorPath: hasDescriptor ? "/projects/\(name)/PROJECT.md" : nil,
        hasDescriptor: hasDescriptor,
        importance: importance,
        lastActivityAt: Date(timeIntervalSince1970: 0)
    )
}

private func resolve(
    _ projects: [ProjectSummary],
    links: [String: String?]
) -> SprintProjectResolver.Resolved? {
    SprintProjectResolver.resolve(projects: projects) { links[$0.name] ?? nil }
}

@Test("the first linked project in the rail's own order wins")
func firstLinkedProjectWins() throws {
    // `activeProjects()` already returns most-important-first, and that ordering is NOT recomputed
    // here: the rail and the brief agreeing about which project matters most is the point, and two
    // places sorting the same list by the same rule is one place too many.
    let resolved = try #require(resolve(
        [project("Ubility", importance: 9), project("CerebralHelm", importance: 5)],
        links: ["Ubility": "Ubility Website", "CerebralHelm": "CerebralHelm"]
    ))

    #expect(resolved.project.name == "Ubility")
    #expect(resolved.linearProject == "Ubility Website")
}

@Test("an unlinked project is skipped rather than blocking the ones behind it")
func unlinkedProjectsAreSkipped() throws {
    // The most important project need not be the one tracked in Linear — a folder can be important
    // and have no tickets at all.
    let resolved = try #require(resolve(
        [project("Scratch", importance: 9), project("CerebralHelm", importance: 5)],
        links: ["Scratch": nil, "CerebralHelm": "CerebralHelm"]
    ))

    #expect(resolved.project.name == "CerebralHelm")
}

@Test("a project with no descriptor is never asked about")
func projectsWithoutDescriptorsAreSkipped() {
    // Only a descriptor can declare a link, so asking is a filesystem read that can only answer nil.
    var asked: [String] = []
    let resolved = SprintProjectResolver.resolve(
        projects: [project("Bare", importance: 9, hasDescriptor: false)]
    ) { summary in
        asked.append(summary.name)
        return "Something"
    }

    #expect(resolved == nil)
    #expect(asked.isEmpty)
}

@Test("a declared-but-blank link is unlinked, not a project named nothing")
func blankLinksAreUnlinked() {
    // An empty string would otherwise reach the API as a real lookup for a project called "".
    #expect(resolve([project("A", importance: 1)], links: ["A": ""]) == nil)
    #expect(resolve([project("A", importance: 1)], links: ["A": "   "]) == nil)
}

@Test("the declared name is carried through with its own spelling")
func declaredNameIsPreserved() throws {
    // Linear matches case-insensitively and echoes its canonical form back, which is what confirms
    // the link. Normalising here would throw away the thing being confirmed.
    let resolved = try #require(resolve([project("A", importance: 1)], links: ["A": "  cerebralhelm  "]))
    #expect(resolved.linearProject == "cerebralhelm")
}

@Test("no linked project anywhere is nil, which is a normal machine")
func noLinkedProjectIsNil() {
    #expect(resolve([project("A", importance: 1), project("B", importance: nil)], links: [:]) == nil)
    #expect(resolve([], links: [:]) == nil)
}
