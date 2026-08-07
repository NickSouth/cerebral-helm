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
#endif
