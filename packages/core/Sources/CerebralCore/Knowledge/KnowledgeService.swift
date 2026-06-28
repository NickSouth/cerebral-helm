/// Portable knowledge capture and search, expressed as a Core port so tool
/// handlers depend on it without importing a storage implementation.
///
/// The pre-Mac foundation binds a mock (`CerebralTools.MockKnowledgeService`);
/// the durable Markdown + SQLite implementation is owned by PRE-DATA (NIC-42) and
/// drops in behind this same protocol. Composition happens at the app layer, so
/// `CerebralTools` never depends on the knowledge package.
public protocol KnowledgeService: Sendable {
    func capture(_ request: NoteCaptureRequest) async throws -> NoteCaptureOutcome
    func search(_ request: NoteSearchRequest) async throws -> NoteSearchOutcome
}

public struct NoteCaptureRequest: Equatable, Sendable {
    public let title: String
    public let body: String
    public let kind: String
    public let project: String?
    public let sensitivity: String?

    public init(title: String, body: String, kind: String, project: String?, sensitivity: String?) {
        self.title = title
        self.body = body
        self.kind = kind
        self.project = project
        self.sensitivity = sensitivity
    }
}

public struct NoteCaptureOutcome: Equatable, Sendable {
    public let noteID: String
    public let path: String
    public let created: Bool

    public init(noteID: String, path: String, created: Bool) {
        self.noteID = noteID
        self.path = path
        self.created = created
    }
}

public struct NoteSearchRequest: Equatable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int?) {
        self.query = query
        self.limit = limit
    }
}

public struct NoteSearchHit: Equatable, Sendable {
    public let noteID: String
    public let title: String
    public let excerpt: String
    public let path: String
    public let updated: String
    public let sensitivity: String?
    public let freshness: String?

    public init(noteID: String, title: String, excerpt: String, path: String, updated: String, sensitivity: String?, freshness: String?) {
        self.noteID = noteID
        self.title = title
        self.excerpt = excerpt
        self.path = path
        self.updated = updated
        self.sensitivity = sensitivity
        self.freshness = freshness
    }
}

public struct NoteSearchOutcome: Equatable, Sendable {
    public let hits: [NoteSearchHit]
    public let truncated: Bool

    public init(hits: [NoteSearchHit], truncated: Bool) {
        self.hits = hits
        self.truncated = truncated
    }
}

/// Failures the knowledge service raises, mirroring the canonical knowledge
/// fixtures (PRD §13.2): a missing or read-only root, a collision with an existing
/// note, or a write failure.
public enum KnowledgeServiceError: Error, Equatable, Sendable {
    case rootUnavailable
    case rootReadOnly
    /// A note already exists at the target path; capture never overwrites (AC-44.3).
    case collision(String)
    case writeFailed(String)
}
