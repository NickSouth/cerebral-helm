import Foundation
import CerebralShared

/// Ties durable mode state and session history together when a mode is applied
/// (FR-MOD-05, FR-MOD-06).
///
/// On a completed application it appends a session record and updates the active
/// mode. Mode and context are persisted **separately**: the caller supplies the
/// context that was active at activation (carried forward or newly chosen), so
/// applying a mode never silently clears a context the user set elsewhere. The
/// clock and identifier generator are injected so records are deterministic in
/// tests (PRD NFR-04).
public struct ModeSessionCoordinator: Sendable {
    private let stateStore: any ModeStateStore
    private let sessionLog: any ModeSessionLog
    private let identifiers: any IdentifierGenerator
    private let clock: any TimeSource

    public init(
        stateStore: any ModeStateStore,
        sessionLog: any ModeSessionLog,
        identifiers: any IdentifierGenerator = UUIDIdentifierGenerator(),
        clock: any TimeSource = SystemClock()
    ) {
        self.stateStore = stateStore
        self.sessionLog = sessionLog
        self.identifiers = identifiers
        self.clock = clock
    }

    /// Records a completed mode application and makes it the active mode. Returns
    /// the appended session so callers can surface or log it.
    @discardableResult
    public func recordApplication(
        modeID: String,
        context: ProjectContext?,
        source: String,
        result: ModeSessionResult,
        configVersion: String
    ) throws -> ModeSession {
        let session = ModeSession(
            id: identifiers.nextIdentifier(for: .session),
            modeID: modeID,
            context: context,
            source: source,
            startedAt: clock.now(),
            endedAt: nil,
            result: result,
            configVersion: configVersion
        )
        try sessionLog.append(session)
        try stateStore.saveActiveModeID(modeID)
        return session
    }
}
