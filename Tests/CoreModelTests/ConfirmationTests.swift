import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared

/// NIC-31 (PRE-SAFETY-4): confirmation coordinator and plan-bound tokens.
///
/// AC-31.1 replay and expired approvals fail; AC-31.2 plan changes require a new
/// confirmation; AC-31.3 approve, review, and cancel are distinct events.

private final class MutableClock: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ instant: Date) { current = instant }

    func advance(to instant: Date) {
        lock.lock(); current = instant; lock.unlock()
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func samplePlan(
    commandID: String = "cmd_00000000abcd",
    arguments: [ConfirmationArgument] = [ConfirmationArgument(name: "hookId", value: "ondraft-dev", sensitive: false)]
) -> ConfirmationPlan {
    ConfirmationPlan(
        commandID: commandID,
        toolID: "hook.run",
        toolVersion: "1.0.0",
        toolPurpose: "Execute a configured allowlisted hook.",
        risk: .shell,
        destination: nil,
        accountOrService: nil,
        dataLeavingDevice: .none,
        reversibility: .unknown,
        arguments: arguments,
        actionSummary: "Run hook ondraft-dev",
        policyReason: "Shell execution requires confirmation."
    )
}

private func makeCoordinator(_ clock: MutableClock, ttl: TimeInterval = 120) -> ConfirmationCoordinator {
    ConfirmationCoordinator(clock: clock, identifiers: SequentialIdentifierGenerator(), ttlSeconds: ttl)
}

@Test("SHA-256 matches the standard test vectors")
func sha256MatchesVectors() {
    #expect(SHA256.hexDigest(of: "") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hexDigest(of: "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test("the plan hash is deterministic and changes when the plan changes (AC-31.2)")
func planHashIsStableAndSensitive() {
    let hash = PlanHash.compute(samplePlan())
    #expect(hash == PlanHash.compute(samplePlan()))
    #expect(hash.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil)

    let changed = PlanHash.compute(samplePlan(arguments: [ConfirmationArgument(name: "hookId", value: "other", sensitive: false)]))
    #expect(hash != changed)
}

@Test("a requested disclosure satisfies the confirmation contract (FR-SAF-04)")
func disclosureIsContractValid() throws {
    let coordinator = makeCoordinator(MutableClock(t0))
    let request = coordinator.requestConfirmation(plan: samplePlan())
    let disclosure = request.disclosure

    // Round-trips through the generated contract.
    let decoded = try CerebralHelmConfirmationDisclosure(data: disclosure.jsonData())
    #expect(decoded.id == disclosure.id)
    #expect(decoded.planHash == disclosure.planHash)

    #expect(disclosure.executionNotice == .executionHasNotHappenedYet)
    #expect(disclosure.choices.defaultFocusedChoice == .review) // approval is never default-focused (§9.5)
    #expect(disclosure.invalidation.singleUseToken)
    #expect(disclosure.invalidation.expires)
    #expect(disclosure.invalidation.invalidAfterPlanChange)
    #expect(disclosure.id.range(of: "^conf_[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil)
    #expect(disclosure.commandID.range(of: "^cmd_[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil)
    #expect(disclosure.planHash == request.token.planHash)
}

@Test("an approved token authorizes exactly once; replay fails (AC-31.1)")
func approveIsSingleUse() {
    let coordinator = makeCoordinator(MutableClock(t0))
    let token = coordinator.requestConfirmation(plan: samplePlan()).token

    #expect(coordinator.decide(token: token, decision: .approve) == .approved(confirmationID: token.confirmationID, commandID: token.commandID))
    #expect(coordinator.decide(token: token, decision: .approve) == .rejected(.alreadyUsed))
}

@Test("an expired token cannot be approved (AC-31.1)")
func expiredTokenIsRefused() {
    let clock = MutableClock(t0)
    let coordinator = makeCoordinator(clock, ttl: 60)
    let token = coordinator.requestConfirmation(plan: samplePlan()).token

    clock.advance(to: t0.addingTimeInterval(120))
    #expect(coordinator.decide(token: token, decision: .approve) == .rejected(.expired))
}

@Test("a changed plan requires a new confirmation (AC-31.2)")
func planChangeRequiresNewConfirmation() {
    let coordinator = makeCoordinator(MutableClock(t0))
    let first = coordinator.requestConfirmation(
        plan: samplePlan(arguments: [ConfirmationArgument(name: "hookId", value: "ondraft-dev", sensitive: false)])
    ).token
    // Same command, changed plan: supersedes the first token.
    let second = coordinator.requestConfirmation(
        plan: samplePlan(arguments: [ConfirmationArgument(name: "hookId", value: "ondraft-prod", sensitive: false)])
    ).token

    #expect(coordinator.decide(token: first, decision: .approve) == .rejected(.planChanged))
    #expect(coordinator.decide(token: second, decision: .approve) == .approved(confirmationID: second.confirmationID, commandID: second.commandID))
}

@Test("approve, review, and cancel are distinct outcomes (AC-31.3)")
func decisionsAreDistinct() {
    let clock = MutableClock(t0)

    // Review does not consume the token; a later approve still succeeds.
    let reviewing = makeCoordinator(clock)
    let reviewToken = reviewing.requestConfirmation(plan: samplePlan()).token
    #expect(reviewing.decide(token: reviewToken, decision: .review) == .reviewed(confirmationID: reviewToken.confirmationID, commandID: reviewToken.commandID))
    #expect(reviewing.decide(token: reviewToken, decision: .approve) == .approved(confirmationID: reviewToken.confirmationID, commandID: reviewToken.commandID))

    // Cancel ends the confirmation; it cannot then be approved.
    let cancelling = makeCoordinator(clock)
    let cancelToken = cancelling.requestConfirmation(plan: samplePlan()).token
    #expect(cancelling.decide(token: cancelToken, decision: .cancel) == .cancelled(confirmationID: cancelToken.confirmationID, commandID: cancelToken.commandID))
    #expect(cancelling.decide(token: cancelToken, decision: .approve) == .rejected(.unknownToken))

    // The three accepted outcomes carry distinct audit event codes.
    let codes = Set([
        ConfirmationResolution.approved(confirmationID: "c", commandID: "x").eventCode,
        ConfirmationResolution.reviewed(confirmationID: "c", commandID: "x").eventCode,
        ConfirmationResolution.cancelled(confirmationID: "c", commandID: "x").eventCode,
    ])
    #expect(codes.count == 3)
}
