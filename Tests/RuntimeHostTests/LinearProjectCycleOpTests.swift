import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// NIC-221 Increment 3: the `getLinearProjectCycle` op reads one project's standing in the active
/// cycle for the project detail window, degrading honestly.
///
/// The point of these tests is the **separation of the failure states**. Four different things can
/// be true — no Linear client on this host, the read failed, the name matches no project, and the
/// project matched but has nothing in the cycle — and the section renders a different thing for
/// each. Any two of them collapsing into one is the bug this file exists to catch, because the
/// collapsed case reads as a confident "nothing to do".

private func cycleOpRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeCycleOpSession(
    linearProjectCycle: (@Sendable (String) async throws -> LinearProjectCycleInfo)? = nil
) throws -> BridgeSession {
    let paths = try WorkspacePaths.temporary(repositoryRoot: cycleOpRepositoryRoot())
    return BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        linearProjectCycle: linearProjectCycle
    )
}

private func cycleOpRequest(_ json: String) -> CerebralHelmBridgeOperationRequest {
    let payload = (try? JSONDecoder().decode([String: JSONAny].self, from: Data(json.utf8))) ?? [:]
    return CerebralHelmBridgeOperationRequest(
        messageID: "brmsg_linearcycle01", operation: .getLinearProjectCycle, payload: payload,
        schemaVersion: "1.0.0", type: .bridgeOperationRequest
    )
}

private struct CycleResultDTO: Decodable {
    struct State: Decodable { let name: String; let type: String; let color: String }
    struct Issue: Decodable {
        let identifier: String
        let title: String
        let url: String
        let priority: Int
        let estimate: Int?
        let state: State
        let labels: [String]
        let assignee: String?
        let assigneeInitials: String?
    }
    struct Cycle: Decodable {
        let id: String
        let number: Int
        let name: String?
        let startsAt: String
        let endsAt: String
    }
    let matchedProject: String?
    let matchedProjectUrl: String?
    let cycle: Cycle?
    let issues: [Issue]
    let truncated: Bool
    let available: Bool
    let reason: String?
}

private func decodeCycleOp(
    _ response: CerebralHelmBridgeOperationResponse
) throws -> CycleResultDTO {
    try JSONDecoder().decode(CycleResultDTO.self, from: JSONEncoder().encode(response.payload))
}

private func sampleInfo(
    matchedProject: String? = "CerebralHelm",
    issues: [LinearProjectCycleInfo.Issue] = [],
    truncated: Bool = false
) -> LinearProjectCycleInfo {
    LinearProjectCycleInfo(
        matchedProject: matchedProject,
        matchedProjectURL: matchedProject.map { _ in "https://linear.app/nick-southey/project/ch" },
        cycle: LinearProjectCycleInfo.Cycle(
            id: "cycle-2", number: 2, name: nil,
            startsAt: "2026-08-17T04:00:00.000Z", endsAt: "2026-08-24T04:00:00.000Z"
        ),
        issues: issues,
        truncated: truncated
    )
}

private let sampleIssue = LinearProjectCycleInfo.Issue(
    identifier: "NIC-221",
    title: "Linear Integration with Projects Widget in Exec Mode",
    url: "https://linear.app/nick-southey/issue/NIC-221/linear-integration",
    priority: 3,
    estimate: 5,
    sortOrder: -99.5,
    state: LinearProjectCycleInfo.State(
        name: "Next-Up", type: "unstarted", color: "#e2e2e2", position: 2
    ),
    labels: ["Feature"],
    assignee: "nickrsouthey",
    assigneeInitials: "NS"
)

@Test("the op returns the cycle and its issues, with Linear's own status colour")
func linearCycleReadSucceeds() async throws {
    let session = try makeCycleOpSession(linearProjectCycle: { _ in
        sampleInfo(issues: [sampleIssue])
    })
    let response = await session.execute(cycleOpRequest(#"{"project":"CerebralHelm"}"#))
    #expect(response.status == .ok)

    let result = try decodeCycleOp(response)
    #expect(result.available == true)
    #expect(result.reason == nil)
    #expect(result.matchedProject == "CerebralHelm")
    #expect(result.cycle?.number == 2)
    #expect(result.issues.count == 1)
    #expect(result.issues[0].identifier == "NIC-221")
    #expect(result.issues[0].state.type == "unstarted")
    #expect(result.issues[0].state.color == "#e2e2e2")
    #expect(result.issues[0].assigneeInitials == "NS")
}

@Test("timestamps cross the bridge as ISO-8601 strings, not numeric offsets")
func linearCycleEncodesTimestampsAsStrings() async throws {
    // Operation payloads go through a plain JSONEncoder, which renders a `Date` as a reference-date
    // offset. The wire shape must not depend on that default, so the dates are already strings.
    let session = try makeCycleOpSession(linearProjectCycle: { _ in sampleInfo() })
    let result = try decodeCycleOp(await session.execute(cycleOpRequest(#"{"project":"X"}"#)))
    #expect(result.cycle?.startsAt == "2026-08-17T04:00:00.000Z")
    #expect(result.cycle?.endsAt == "2026-08-24T04:00:00.000Z")
}

@Test("a host with no Linear client reports unavailable, not an empty cycle")
func linearCycleUnavailableWithoutClient() async throws {
    let session = try makeCycleOpSession() // no closure injected
    let result = try decodeCycleOp(await session.execute(cycleOpRequest(#"{"project":"X"}"#)))
    #expect(result.available == false)
    #expect(result.reason == nil)
    #expect(result.issues.isEmpty)
}

@Test("a read that fails reports a reason rather than an empty cycle")
func linearCycleFailureReportsReason() async throws {
    struct Boom: Error {}
    let session = try makeCycleOpSession(linearProjectCycle: { _ in throw Boom() })
    let result = try decodeCycleOp(await session.execute(cycleOpRequest(#"{"project":"X"}"#)))
    // Available — this host CAN read Linear — but this attempt did not work, which is a third
    // state again: "we could not read it" is not "there is nothing in it".
    #expect(result.available == true)
    #expect(result.reason != nil)
    #expect(result.issues.isEmpty)
}

@Test("a name matching no project is distinguishable from an empty cycle")
func linearCycleUnmatchedProject() async throws {
    let unmatched = try decodeCycleOp(await makeCycleOpSession(linearProjectCycle: { _ in
        LinearProjectCycleInfo(
            matchedProject: nil, matchedProjectURL: nil, cycle: nil, issues: [], truncated: false
        )
    }).execute(cycleOpRequest(#"{"project":"CerebralHlem"}"#)))

    let emptyButLinked = try decodeCycleOp(await makeCycleOpSession(linearProjectCycle: { _ in
        sampleInfo(issues: [])
    }).execute(cycleOpRequest(#"{"project":"CerebralHelm"}"#)))

    // Both have zero issues and both succeeded. Only `matchedProject` separates a broken link from
    // a quiet week — and the section must say something different for each.
    #expect(unmatched.issues.isEmpty && emptyButLinked.issues.isEmpty)
    #expect(unmatched.available == true && emptyButLinked.available == true)
    #expect(unmatched.matchedProject == nil)
    #expect(emptyButLinked.matchedProject == "CerebralHelm")
    #expect(emptyButLinked.cycle?.number == 2)
}

@Test("the project URL crosses the wire as matchedProjectUrl, not matchedProjectURL")
func linearCycleProjectUrlKeyCasing() async throws {
    // Swift writes `URL`, JSON writes `Url`. If these ever drift, the web layer reads `undefined`
    // and silently loses the "open in Linear" affordance, with nothing failing anywhere else.
    let session = try makeCycleOpSession(linearProjectCycle: { _ in sampleInfo() })
    let response = await session.execute(cycleOpRequest(#"{"project":"CerebralHelm"}"#))
    #expect(response.payload["matchedProjectUrl"] != nil)
    #expect(response.payload["matchedProjectURL"] == nil)
    #expect(try decodeCycleOp(response).matchedProjectUrl?.isEmpty == false)
}

@Test("a truncated page says so rather than looking complete")
func linearCycleReportsTruncation() async throws {
    let session = try makeCycleOpSession(linearProjectCycle: { _ in
        sampleInfo(issues: [sampleIssue], truncated: true)
    })
    #expect(try decodeCycleOp(await session.execute(cycleOpRequest(#"{"project":"X"}"#))).truncated)
}

@Test("a missing or blank project name is refused as invalid input")
func linearCycleRefusesBlankProject() async throws {
    let session = try makeCycleOpSession(linearProjectCycle: { _ in sampleInfo() })
    #expect(await session.execute(cycleOpRequest("{}")).status == .error)
    #expect(await session.execute(cycleOpRequest(#"{"project":"  "}"#)).status == .error)
}

@Test("the payload is shaped as a read, with a pinned key set")
func linearCycleIsShapedAsARead() async throws {
    // Opening a project window is looking, not acting — so unlike the write ops this payload has
    // no `awaitingConfirmation` to carry. Pinning the whole key set also fixes the wire contract
    // the dashboard decodes, so a field renamed in Swift fails here rather than in the browser.
    let session = try makeCycleOpSession(linearProjectCycle: { _ in
        sampleInfo(issues: [sampleIssue])
    })
    let response = await session.execute(cycleOpRequest(#"{"project":"CerebralHelm"}"#))
    #expect(Set(response.payload.keys) == [
        "matchedProject", "matchedProjectUrl", "cycle", "issues", "truncated", "available", "reason"
    ])
}

@Test("a nil field crosses the wire as an explicit null, never as an absent key")
func linearCycleEncodesExplicitNulls() async throws {
    // Swift's synthesized Codable omits nil optionals. The web layer declares these as `T | null`
    // and separates a broken link from a quiet cycle with `matchedProject === null` — which is
    // silently false against `undefined`. So every key is present, whatever its value.
    let session = try makeCycleOpSession(linearProjectCycle: { _ in
        LinearProjectCycleInfo(
            matchedProject: nil, matchedProjectURL: nil, cycle: nil, issues: [], truncated: false
        )
    })
    let response = await session.execute(cycleOpRequest(#"{"project":"CerebralHlem"}"#))

    // Present-and-null, not missing: the same key set as the fully-populated case above.
    #expect(Set(response.payload.keys) == [
        "matchedProject", "matchedProjectUrl", "cycle", "issues", "truncated", "available", "reason"
    ])
    let json = String(decoding: try JSONEncoder().encode(response.payload), as: UTF8.self)
    #expect(json.contains("\"matchedProject\":null"))
    #expect(json.contains("\"reason\":null"))
    #expect(json.contains("\"cycle\":null"))
}

@Test("an unnamed cycle and an unassigned issue also encode their nulls")
func linearCycleEncodesNestedNulls() async throws {
    let issue = LinearProjectCycleInfo.Issue(
        identifier: "NIC-227", title: "Grammar-constrained decoding", url: "https://linear.app/x",
        priority: 3, estimate: nil, sortOrder: 1,
        state: LinearProjectCycleInfo.State(
            name: "Todo", type: "unstarted", color: "#e2e2e2", position: 1
        ),
        labels: [], assignee: nil, assigneeInitials: nil
    )
    let session = try makeCycleOpSession(linearProjectCycle: { _ in sampleInfo(issues: [issue]) })
    let response = await session.execute(cycleOpRequest(#"{"project":"CerebralHelm"}"#))
    let json = String(decoding: try JSONEncoder().encode(response.payload), as: UTF8.self)
    // The common shape in a personal workspace: no estimate, no assignee, and an unnamed cycle.
    #expect(json.contains("\"estimate\":null"))
    #expect(json.contains("\"assignee\":null"))
    #expect(json.contains("\"assigneeInitials\":null"))
    #expect(json.contains("\"name\":null"))
}
