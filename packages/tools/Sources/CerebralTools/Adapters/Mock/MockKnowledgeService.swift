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

    /// The mock's stand-in knowledge root, reported as the source location.
    public static let root = "/mock/knowledge"

    public var rootState: RootState
    public var hits: [NoteSearchHit]
    /// Canned library entries for `list`, in the order the mock returns them.
    public var entries: [NoteListEntry]
    /// Canned note bodies for `read`, keyed by the entry path.
    public var bodies: [String: String]

    public init(
        rootState: RootState = .writable,
        hits: [NoteSearchHit] = [],
        entries: [NoteListEntry] = [],
        bodies: [String: String] = [:]
    ) {
        self.rootState = rootState
        self.hits = hits
        self.entries = entries
        self.bodies = bodies
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

    public func list(_ request: NoteListRequest) async throws -> NoteListOutcome {
        if rootState == .missing {
            throw KnowledgeServiceError.rootUnavailable
        }
        let limited = request.limit.map { Array(entries.prefix($0)) } ?? entries
        return NoteListOutcome(
            root: Self.root, entries: limited, total: entries.count,
            truncated: limited.count < entries.count
        )
    }

    public func read(_ request: NoteReadRequest) async throws -> NoteReadOutcome {
        if rootState == .missing {
            throw KnowledgeServiceError.rootUnavailable
        }
        guard let entry = entries.first(where: { $0.path == request.path }) else {
            throw KnowledgeServiceError.noteNotFound("No note at \(request.path) in the knowledge root.")
        }
        return NoteReadOutcome(
            root: Self.root,
            path: entry.path,
            title: entry.title,
            noteID: entry.noteID,
            frontmatter: [:],
            body: bodies[entry.path] ?? "",
            updated: entry.updated
        )
    }
}
