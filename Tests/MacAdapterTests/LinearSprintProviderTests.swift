// NIC-228: resolving a project and projecting its Linear cycle down to a Sprint.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore

/// The glue between a rule and an API. The rule itself is tested in `SprintProjectResolverTests`
/// and the arithmetic in `SprintPaceTests`; what is worth covering here is the **projection** —
/// which Linear fields survive into a model's context, and how each failure is renamed on the way
/// out so the reader is asked for the right thing.

private struct ScriptedProjectsProvider: ActiveProjectsProvider {
    let projects: [ProjectSummary]
    var failure: ActiveProjectsError?

    func activeProjects() throws -> [ProjectSummary] {
        if let failure { throw failure }
        return projects
    }
}

private struct ScriptedCycleProvider: LinearProjectCycleProviding {
    var cycle: LinearProjectCycle?
    var failure: LinearAPIError?

    func projectCycle(named projectName: String) async throws -> LinearProjectCycle {
        if let failure { throw failure }
        return cycle ?? LinearProjectCycle(matchedProject: projectName, cycle: nil, issues: [], truncated: false)
    }
}

private func project(_ name: String, importance: Int? = 5) -> ProjectSummary {
    ProjectSummary(
        id: name, name: name, path: "/projects/\(name)",
        descriptorPath: "/projects/\(name)/PROJECT.md", hasDescriptor: true,
        importance: importance, lastActivityAt: Date(timeIntervalSince1970: 0)
    )
}

private func provider(
    projects: [ProjectSummary] = [project("CerebralHelm")],
    projectsFailure: ActiveProjectsError? = nil,
    cycle: LinearProjectCycle? = nil,
    cycleFailure: LinearAPIError? = nil,
    link: String? = "CerebralHelm"
) -> LinearSprintProvider {
    LinearSprintProvider(
        projects: ScriptedProjectsProvider(projects: projects, failure: projectsFailure),
        cycles: ScriptedCycleProvider(cycle: cycle, failure: cycleFailure),
        linearProject: { _ in link }
    )
}

private func linearIssue(
    _ identifier: String,
    stateName: String = "Next-Up",
    stateType: String = "unstarted",
    estimate: Int? = 5
) -> LinearProjectCycle.Issue {
    LinearProjectCycle.Issue(
        identifier: identifier,
        title: "Ship \(identifier)",
        url: "https://linear.app/nick-southey/issue/\(identifier)",
        priority: 2,
        estimate: estimate,
        sortOrder: -99.5,
        state: LinearProjectCycle.State(name: stateName, type: stateType, color: "#e2e2e2", position: 2),
        labels: ["Feature"],
        assignee: "nickrsouthey",
        assigneeInitials: "NS"
    )
}

// MARK: - Projection

@Test("the cycle is projected down to what a brief needs and no more")
func projectionIsNarrow() async throws {
    let sprint = try await provider(cycle: LinearProjectCycle(
        matchedProject: "CerebralHelm",
        matchedProjectURL: "https://linear.app/nick-southey/project/cerebralhelm",
        cycle: LinearProjectCycle.Cycle(
            id: "c3", number: 3, name: nil,
            startsAt: Date(timeIntervalSince1970: 1_755_000_000),
            endsAt: Date(timeIntervalSince1970: 1_755_604_800)
        ),
        issues: [linearIssue("NIC-250")],
        truncated: false
    )).currentSprint()

    #expect(sprint.projectName == "CerebralHelm")
    #expect(sprint.cycle?.number == 3)

    let issue = try #require(sprint.issues.first)
    #expect(issue.identifier == "NIC-250")
    #expect(issue.stateName == "Next-Up")
    // Grouped on Linear's TYPE. "Next-Up" and "Todo" are both `unstarted`, and a pace computed from
    // names would break the first time a column was renamed.
    #expect(issue.state == .unstarted)
    #expect(issue.estimate == 5)
    #expect(issue.labels == ["Feature"])
    // `Sprint` carries no url, colour, sortOrder or assignee initials, by construction. Every field
    // withheld is one a model cannot misread or quote back — and a report's destinations are
    // registered quick actions, never links a model chose.
}

@Test("an unknown workflow state counts as neither done nor in flight")
func unknownStateIsBacklog() async throws {
    // Defaulting to `backlog` keeps a state this build has not seen out of both counts, rather than
    // inflating either. Linear adding a sixth type should not silently move the pace.
    let sprint = try await provider(cycle: LinearProjectCycle(
        matchedProject: "CerebralHelm", cycle: nil,
        issues: [linearIssue("NIC-1", stateName: "Paused", stateType: "hibernating")],
        truncated: false
    )).currentSprint()

    #expect(sprint.issues.first?.state == .backlog)
    #expect(sprint.issues.first?.stateName == "Paused")
}

@Test("Linear's own spelling of the project comes back, not the descriptor's")
func canonicalProjectNameIsReturned() async throws {
    // Linear matches case-insensitively and echoes its canonical form. Carrying that back is what
    // confirms which project was matched rather than assuming the descriptor got it right.
    let sprint = try await provider(
        cycle: LinearProjectCycle(matchedProject: "CerebralHelm", cycle: nil, issues: [], truncated: false),
        link: "cerebralhelm"
    ).currentSprint()

    #expect(sprint.projectName == "CerebralHelm")
}

// MARK: - Failures

@Test("a project Linear does not have is named, never reported as an empty sprint")
func unmatchedProjectIsNamed() async {
    // A misspelled `linear_project` returns zero issues, byte-identical to a correctly-linked
    // project with an empty cycle. Without this the brief would report a typo as "nothing to do".
    let subject = provider(
        cycle: LinearProjectCycle(matchedProject: nil, cycle: nil, issues: [], truncated: false),
        link: "CerebralHlem"
    )

    await #expect(throws: SprintError.projectNotFound("CerebralHlem")) {
        try await subject.currentSprint()
    }
}

@Test("no project declares a link, which is a normal machine rather than a fault")
func noLinkIsItsOwnOutcome() async {
    await #expect(throws: SprintError.noLinkedProject) {
        try await provider(link: nil).currentSprint()
    }
}

@Test("an unreadable projects folder is not reported as a Linear problem")
func projectsFailureIsNotBlamedOnLinear() async {
    // Saying "Linear couldn't be read" here would send the reader to re-paste an API key that was
    // never the issue.
    await #expect(throws: SprintError.unavailable("The projects folder couldn\u{2019}t be read.")) {
        try await provider(projectsFailure: .rootUnavailable("/projects")).currentSprint()
    }
}

@Test("each Linear failure keeps its own remedy")
func linearFailuresAreMapped() async {
    await #expect(throws: SprintError.credentialsMissing) {
        try await provider(cycleFailure: .credentialsMissing).currentSprint()
    }
    await #expect(throws: SprintError.unavailable("Linear rejected the stored API key.")) {
        try await provider(cycleFailure: .unauthorized).currentSprint()
    }
    await #expect(throws: SprintError.unavailable("Linear is rate-limiting requests right now.")) {
        try await provider(cycleFailure: .rateLimited).currentSprint()
    }
    // A missing key and a rejected key need different things from the reader: one is setup, the
    // other is a key that has been revoked or rotated.
}
#endif
