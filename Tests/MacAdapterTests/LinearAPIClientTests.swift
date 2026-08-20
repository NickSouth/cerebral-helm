// Quick actions phase 4, action 3: the Linear GraphQL client.
//
// The contract was verified live against api.linear.app on 2026-08-03 (endpoint, header format,
// issueCreate/IssueCreateInput field names, Issue.identifier/url). These tests cover the pure
// decoding and error-translation the transport depends on; the live round trip is manual smoke.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

@Test("the mutation sends values as GraphQL variables, never interpolated into the query")
func linearMutationUsesVariables() {
    // A title containing a quote or a brace is then data, not syntax, and cannot alter the
    // mutation — the GraphQL equivalent of the host-fixed search URL.
    #expect(LinearAPIClient.createIssueMutation.contains("$input: IssueCreateInput!"))
    #expect(LinearAPIClient.createIssueMutation.contains("issueCreate(input: $input)"))
    // The response selects what the output contract promises, and nothing is constructed locally.
    #expect(LinearAPIClient.createIssueMutation.contains("identifier"))
    #expect(LinearAPIClient.createIssueMutation.contains("url"))
}

@Test("the workspace query nests projects and labels inside their team")
func linearWorkspaceQueryIsScoped() {
    // Flattening would let the form offer a project from another team, which Linear rejects at
    // write time; nesting makes that impossible to express.
    let query = LinearAPIClient.workspaceQuery
    let teamsIndex = try? #require(query.range(of: "teams("))
    let projectsIndex = try? #require(query.range(of: "projects("))
    #expect(teamsIndex != nil && projectsIndex != nil)
    #expect(query.range(of: "labels(") != nil)
}

@Test("a team decodes with its scoped projects and labels")
func linearDecodesTeam() throws {
    let node: [String: Any] = [
        "id": "team-1",
        "key": "NIC",
        "name": "CerebralHelm Development",
        "projects": ["nodes": [["id": "p1", "name": "CerebralHelm"]]],
        "labels": ["nodes": [["id": "l1", "name": "MVP Polish"], ["id": "l2", "name": "Tech Debt"]]]
    ]
    let team = try #require(LinearAPIClient.decodeTeam(node))
    #expect(team.key == "NIC")
    #expect(team.projects.map(\.name) == ["CerebralHelm"])
    #expect(team.labels.count == 2)
}

@Test("a partially-shaped team or option is dropped rather than rendered blank")
func linearDropsMalformedNodes() {
    // A dropdown must never offer an option that cannot be filed against.
    #expect(LinearAPIClient.decodeTeam(["id": "team-1", "key": "NIC"]) == nil)

    let mixed: Any = ["nodes": [["id": "p1", "name": "Good"], ["id": "p2"], ["name": "No id"]]]
    #expect(LinearAPIClient.options(in: mixed).map(\.id) == ["p1"])
    // A missing container is an empty list, not a crash.
    #expect(LinearAPIClient.options(in: nil).isEmpty)
}

@Test("a missing key is a notFound with the remedy, not a bare unavailable")
func linearMapsCredentialsMissing() {
    // The first-run case, fixable in one step — so the message says where.
    guard case let .notFound(message) = LinearAPIClient.capabilityError(from: .credentialsMissing) else {
        Issue.record("a missing key must map to notFound"); return
    }
    #expect(message.contains("Settings"))

    #expect(LinearAPIClient.capabilityError(from: .unauthorized) == .permissionDenied)
    #expect(LinearAPIClient.capabilityError(from: .rateLimited) == .adapterFailure("Linear's rate limit was reached. Try again shortly."))
    #expect(LinearAPIClient.capabilityError(from: .providerFailed("boom")) == .adapterFailure("boom"))
}

@Test("a GraphQL errors array reports Linear's own message")
func linearReportsGraphQLErrors() {
    // GraphQL answers 200 even when the operation failed, so `errors` is the real status — a
    // caller reading only the HTTP code would report a ticket that was never filed.
    let message = LinearAPIClient.message(from: [["message": "Team not found"]])
    #expect(message.contains("Team not found"))
    #expect(LinearAPIClient.message(from: [[:]]).isEmpty == false)
}

// MARK: - Project cycle (NIC-221)

@Test("the project-cycle query filters on project name and the active cycle, via variables")
func linearProjectCycleQueryIsFiltered() {
    let query = LinearAPIClient.projectCycleQuery
    // The project name is a variable, never interpolated: a name containing a brace or a quote is
    // data, not syntax — the same rule the create mutation follows.
    #expect(query.contains("$project: String!"))
    #expect(query.contains("eqIgnoreCase: $project"))
    // Both halves of the filter must be present; either alone returns the wrong set entirely.
    #expect(query.contains("cycle: { isActive: { eq: true } }"))
    // The cycles root exists so the empty case can still name the cycle.
    #expect(query.contains("cycles(first: 1"))
    // A truncated page has to be detectable.
    #expect(query.contains("hasNextPage"))
    // Issue descriptions are deliberately not requested.
    #expect(query.contains("description") == false)
}

@Test("an issue decodes with its state, labels, estimate and assignee")
func linearDecodesIssue() throws {
    let node: [String: Any] = [
        "identifier": "NIC-221",
        "title": "Linear Integration with Projects Widget in Exec Mode",
        "url": "https://linear.app/nick-southey/issue/NIC-221/linear-integration",
        "priority": 3,
        "estimate": 5,
        "sortOrder": -99.5,
        "state": ["name": "Next-Up", "type": "unstarted", "color": "#e2e2e2", "position": 2],
        "labels": ["nodes": [["name": "Feature"]]],
        "assignee": ["displayName": "Nick"]
    ]

    let issue = try #require(LinearAPIClient.decodeIssue(node))
    #expect(issue.identifier == "NIC-221")
    #expect(issue.priority == 3)
    #expect(issue.estimate == 5)
    #expect(issue.sortOrder == -99.5)
    #expect(issue.labels == ["Feature"])
    #expect(issue.assignee == "Nick")
    // The state's TYPE is what grouping keys off — the name is user-renameable.
    #expect(issue.state.type == "unstarted")
    #expect(issue.state.color == "#e2e2e2")
}

@Test("an unassigned, unestimated, unlabelled issue still decodes")
func linearDecodesSparseIssue() throws {
    // The common shape in a personal workspace — none of these absences is an error.
    let node: [String: Any] = [
        "identifier": "NIC-227",
        "title": "Grammar-constrained decoding",
        "url": "https://linear.app/nick-southey/issue/NIC-227/grammar",
        "priority": 0,
        "state": ["name": "Todo", "type": "unstarted", "color": "#bec2c8"]
    ]

    let issue = try #require(LinearAPIClient.decodeIssue(node))
    #expect(issue.estimate == nil)
    #expect(issue.assignee == nil)
    #expect(issue.labels.isEmpty)
    #expect(issue.priority == 0)
}

@Test("an issue missing a field the row cannot render is dropped, not blanked")
func linearDropsPartialIssue() {
    // A row rendered with blanks claims to be an issue you can open; this one would not open.
    #expect(LinearAPIClient.decodeIssue(["title": "No identifier", "url": "https://x"]) == nil)
    #expect(LinearAPIClient.decodeIssue([
        "identifier": "NIC-1", "title": "No state", "url": "https://x"
    ]) == nil)
}

@Test("a cycle decodes its number and both ISO-8601 timestamps")
func linearDecodesCycle() throws {
    let cycle = try #require(LinearAPIClient.decodeCycle([
        "id": "cycle-2",
        "number": 2,
        "startsAt": "2026-08-17T04:00:00.000Z",
        "endsAt": "2026-08-24T04:00:00.000Z"
    ]))
    #expect(cycle.number == 2)
    #expect(cycle.name == nil) // cycles are usually unnamed
    #expect(cycle.endsAt.timeIntervalSince(cycle.startsAt) == 7 * 24 * 60 * 60)
}

@Test("a timestamp without fractional seconds still parses")
func linearDecodesCycleWithoutFractionalSeconds() throws {
    // Linear sends fractional seconds today, but the format is not promised — falling back keeps
    // the cycle header from blanking if it ever changes.
    let cycle = try #require(LinearAPIClient.decodeCycle([
        "id": "c", "number": 9, "startsAt": "2026-08-17T04:00:00Z", "endsAt": "2026-08-24T04:00:00Z"
    ]))
    #expect(cycle.number == 9)
}

@Test("the reported cycle is the one the issues are actually in")
func linearResolvesCycleFromIssues() throws {
    // The header must never name a different cycle from the rows beneath it, so the issues' own
    // cycle wins over the workspace-wide active one.
    let issueNodes: [[String: Any]] = [[
        "cycle": [
            "id": "from-issue", "number": 2,
            "startsAt": "2026-08-17T04:00:00.000Z", "endsAt": "2026-08-24T04:00:00.000Z"
        ]
    ]]
    let payload: [String: Any] = ["cycles": ["nodes": [[
        "id": "from-root", "number": 7,
        "startsAt": "2026-08-17T04:00:00.000Z", "endsAt": "2026-08-24T04:00:00.000Z"
    ]]]]

    let cycle = try #require(LinearAPIClient.resolveCycle(issueNodes: issueNodes, payload: payload))
    #expect(cycle.id == "from-issue")
}

@Test("with no issues, the cycle still comes back from the cycles root")
func linearResolvesCycleWhenProjectHasNoIssues() throws {
    // This is what separates "no active cycle" from "a cycle is running and this project has
    // nothing in it" — the empty state names the cycle rather than claiming there is none.
    let payload: [String: Any] = ["cycles": ["nodes": [[
        "id": "from-root", "number": 2,
        "startsAt": "2026-08-17T04:00:00.000Z", "endsAt": "2026-08-24T04:00:00.000Z"
    ]]]]

    let cycle = try #require(LinearAPIClient.resolveCycle(issueNodes: [], payload: payload))
    #expect(cycle.number == 2)
}

@Test("between cycles, there is no cycle to report")
func linearResolvesNoCycle() {
    #expect(LinearAPIClient.resolveCycle(issueNodes: [], payload: ["cycles": ["nodes": []]]) == nil)
}

@Test("a blank project name is refused before any request is made")
func linearRefusesBlankProjectName() async {
    // Otherwise Linear is asked for a project called "" and answers with an empty set, which the
    // surface would render as "nothing in this cycle" — a different fact.
    let client = LinearAPIClient(secretStore: FailingSecretStore())
    await #expect(throws: LinearAPIError.self) {
        _ = try await client.projectCycle(named: "   ")
    }
}

/// A store that never yields a value — enough to prove the blank-name guard runs *before* the
/// credential read, since a name that got past it would fail with `credentialsMissing` instead.
private struct FailingSecretStore: SecretStoreManaging {
    func store(reference: String, value: String) async throws {}
    func readValue(reference: String) async throws -> String {
        throw LinearAPIError.credentialsMissing
    }
    func delete(reference: String) async throws {}
}

#endif
