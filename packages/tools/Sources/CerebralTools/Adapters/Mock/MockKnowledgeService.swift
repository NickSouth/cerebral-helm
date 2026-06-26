import CerebralCore

/// Deterministic mock knowledge service for the pre-Mac foundation.
///
/// Stands in for the durable PRE-DATA implementation behind the Core
/// ``KnowledgeService`` port. Configurable root availability reproduces the
/// canonical knowledge failure fixtures; canned hits drive search.
public struct MockKnowledgeService: KnowledgeService {
    public enum RootState: Sendable {
        case writable
        case readOnly
        case missing
    }

    public var rootState: RootState
    public var hits: [NoteSearchHit]

    public init(rootState: RootState = .writable, hits: [NoteSearchHit] = []) {
        self.rootState = rootState
        self.hits = hits
    }

    public func capture(_ request: NoteCaptureRequest) async throws -> NoteCaptureOutcome {
        switch rootState {
        case .missing:
            throw KnowledgeServiceError.rootUnavailable
        case .readOnly:
            throw KnowledgeServiceError.rootReadOnly
        case .writable:
            let noteID = "ch-\(request.kind)-001"
            return NoteCaptureOutcome(noteID: noteID, path: "inbox/\(noteID).md", created: true)
        }
    }

    public func search(_ request: NoteSearchRequest) async throws -> NoteSearchOutcome {
        if rootState == .missing {
            throw KnowledgeServiceError.rootUnavailable
        }
        let limited = request.limit.map { Array(hits.prefix($0)) } ?? hits
        return NoteSearchOutcome(hits: limited, truncated: limited.count < hits.count)
    }
}
