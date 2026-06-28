import Foundation
import CerebralContracts
import CerebralShared

/// A user decision on a pending confirmation. The three choices are distinct and
/// produce distinct outcomes (AC-31.3).
public enum ConfirmationDecision: String, Equatable, Sendable {
    case approve
    case review
    case cancel
}

/// A single-use approval token bound to a command and a plan hash (FR-SAF-05).
/// Presenting it back authorizes execution exactly once, only while the plan is
/// unchanged and unexpired.
public struct ConfirmationToken: Equatable, Sendable {
    public let value: String
    public let confirmationID: String
    public let commandID: String
    public let planHash: String
    public let expiresAt: Date
}

/// The disclosure plus its single-use token, returned when a confirmation is
/// requested. The disclosure is the wire contract the dashboard renders; the
/// token is held by the caller and presented back to decide.
public struct ConfirmationRequest {
    public let disclosure: CerebralHelmConfirmationDisclosure
    public let token: ConfirmationToken
}

/// Why a decision was refused.
public enum ConfirmationRejection: String, Equatable, Sendable {
    case unknownToken
    case alreadyUsed
    case expired
    case planChanged
}

/// The outcome of deciding a confirmation. Approve, review, and cancel are
/// distinct cases with distinct audit event codes (AC-31.3).
public enum ConfirmationResolution: Equatable, Sendable {
    case approved(confirmationID: String, commandID: String)
    case reviewed(confirmationID: String, commandID: String)
    case cancelled(confirmationID: String, commandID: String)
    case rejected(ConfirmationRejection)

    /// Stable audit event code, or `nil` for a rejection.
    public var eventCode: String? {
        switch self {
        case .approved: return "confirmation.approved"
        case .reviewed: return "confirmation.reviewed"
        case .cancelled: return "confirmation.cancelled"
        case .rejected: return nil
        }
    }
}

/// Owns the confirmation lifecycle outside any model (G-05): it builds
/// disclosures, mints expiring single-use plan-bound tokens, and enforces that
/// replayed, expired, or plan-changed approvals fail (FR-SAF-04, FR-SAF-05).
///
/// Lock-serialized so concurrent decisions cannot double-spend a token.
///
/// Pending tokens live behind a ``ConfirmationStore`` seam. The default in-memory
/// store reproduces the historical per-process behavior; a durable store (SQLite,
/// NIC-112) makes a confirmation requested in one invocation decidable in the
/// next. Store failures are handled fail-closed — a decision that cannot read or
/// durably record state authorizes nothing.
public final class ConfirmationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any TimeSource
    private let identifiers: any IdentifierGenerator
    private let ttl: TimeInterval
    private let store: any ConfirmationStore

    public init(
        clock: any TimeSource = SystemClock(),
        identifiers: any IdentifierGenerator = UUIDIdentifierGenerator(),
        ttlSeconds: TimeInterval = 120,
        store: any ConfirmationStore = InMemoryConfirmationStore()
    ) {
        self.clock = clock
        self.identifiers = identifiers
        self.ttl = ttlSeconds
        self.store = store
    }

    /// Creates a disclosure and single-use token for `plan`, superseding any
    /// prior pending confirmation for the same command. A superseded token can no
    /// longer be approved, so a changed plan requires a fresh confirmation
    /// (AC-31.2).
    public func requestConfirmation(plan: ConfirmationPlan) -> ConfirmationRequest {
        lock.lock()
        defer { lock.unlock() }

        let now = clock.now()
        let planHash = PlanHash.compute(plan)
        let confirmationID = identifiers.nextIdentifier(for: .confirmation)
        let tokenValue = identifiers.nextIdentifier(for: .confirmation)
        let expiresAt = now.addingTimeInterval(ttl)

        // Best-effort durability: the in-memory store never fails; a durable store
        // that fails here leaves no pending row, so a later decide fails closed (the
        // token resolves to `unknownToken`) rather than authorizing unrecorded work.
        try? store.save(
            PendingConfirmation(
                commandID: plan.commandID,
                confirmationID: confirmationID,
                tokenValue: tokenValue,
                planHash: planHash,
                expiresAt: expiresAt,
                used: false
            )
        )

        return ConfirmationRequest(
            disclosure: Self.disclosure(for: plan, id: confirmationID, planHash: planHash, expiresAt: expiresAt),
            token: ConfirmationToken(
                value: tokenValue,
                confirmationID: confirmationID,
                commandID: plan.commandID,
                planHash: planHash,
                expiresAt: expiresAt
            )
        )
    }

    /// Resolves a confirmation. Approve consumes the token (replay fails);
    /// review inspects without consuming; cancel ends it. Expired, superseded, or
    /// already-used tokens are refused (AC-31.1, AC-31.2).
    public func decide(token: ConfirmationToken, decision: ConfirmationDecision) -> ConfirmationResolution {
        lock.lock()
        defer { lock.unlock() }

        // A store failure is treated as "no pending row": the decision fails closed
        // (nothing is authorized) rather than bypassing the guard.
        guard let entry = (try? store.load(commandID: token.commandID)) ?? nil else {
            return .rejected(.unknownToken)
        }
        // A newer confirmation for this command has superseded the token.
        guard entry.confirmationID == token.confirmationID, entry.tokenValue == token.value, entry.planHash == token.planHash else {
            return .rejected(.planChanged)
        }
        if clock.now() >= entry.expiresAt {
            try? store.delete(commandID: token.commandID)
            return .rejected(.expired)
        }

        switch decision {
        case .review:
            // Inspecting does not consume the token or change state.
            return .reviewed(confirmationID: entry.confirmationID, commandID: token.commandID)
        case .approve:
            if entry.used { return .rejected(.alreadyUsed) }
            var updated = entry
            updated.used = true
            // Only authorize once the single-use consumption is durably recorded, so
            // a replay after a restart cannot find the token still unused.
            guard (try? store.save(updated)) != nil else { return .rejected(.unknownToken) }
            return .approved(confirmationID: entry.confirmationID, commandID: token.commandID)
        case .cancel:
            if entry.used { return .rejected(.alreadyUsed) }
            guard (try? store.delete(commandID: token.commandID)) != nil else { return .rejected(.unknownToken) }
            return .cancelled(confirmationID: entry.confirmationID, commandID: token.commandID)
        }
    }

    private static func disclosure(
        for plan: ConfirmationPlan,
        id: String,
        planHash: String,
        expiresAt: Date
    ) -> CerebralHelmConfirmationDisclosure {
        CerebralHelmConfirmationDisclosure(
            accountOrService: plan.accountOrService,
            actionSummary: plan.actionSummary,
            arguments: plan.arguments.map { Argument(name: $0.name, sensitive: $0.sensitive, value: $0.value) },
            choices: Choices(
                approve: Approve(label: "Approve"),
                cancel: Cancel(label: "Cancel"),
                // Approval is never the default-focused choice (PRD §9.5).
                defaultFocusedChoice: .review,
                review: Review(label: "Review")
            ),
            commandID: plan.commandID,
            dataLeavingDevice: plan.dataLeavingDevice,
            destination: plan.destination,
            executionNotice: .executionHasNotHappenedYet,
            expiresAt: expiresAt,
            id: id,
            invalidation: Invalidation(expires: true, invalidAfterPlanChange: true, singleUseToken: true),
            planHash: planHash,
            policyReason: plan.policyReason,
            reversibility: plan.reversibility,
            risk: plan.risk,
            schemaVersion: "1.0.0",
            tool: Tool(id: plan.toolID, purpose: plan.toolPurpose, version: plan.toolVersion)
        )
    }
}
