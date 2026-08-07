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
    /// Enumerates the durable notes under the knowledge root (NIC-162). Reads the
    /// Markdown itself rather than the derived index, so a note written outside
    /// CerebralHelm — by hand, or in Obsidian — is listed before any rebuild.
    func list(_ request: NoteListRequest) async throws -> NoteListOutcome
    /// Reads one note by its root-relative path (NIC-162). Read-only: nothing in
    /// this port writes, and the path never resolves outside the knowledge root.
    func read(_ request: NoteReadRequest) async throws -> NoteReadOutcome
    /// Where one note actually lives on disk, for handing to an editor.
    ///
    /// A location question answered without reading the file: `note.open` needs an
    /// absolute path and nothing else, and opening a note should not depend on it
    /// being readable text. The containment rule is the **same** one ``read`` uses —
    /// one resolver, so a path this admits and a path that reads can never diverge.
    func locate(_ request: NoteReadRequest) async throws -> NoteLocation
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

/// One note in a library listing (NIC-162), projected from its Markdown file.
///
/// `path` — root-relative, forward-slashed — is the stable handle: it addresses a
/// note the same way whether CerebralHelm wrote it or the user did. `noteID` is
/// therefore optional: only a note carrying CerebralHelm frontmatter has one, and
/// a file created in another editor is still a first-class note.
public struct NoteListEntry: Equatable, Sendable {
    public let path: String
    public let title: String
    public let noteID: String?
    /// The containing folder, root-relative (`inbox`, `projects/atlas`), empty at
    /// the root — the hierarchy FR-KNW-03 defines, for grouping by project/area.
    public let folder: String
    public let project: String?
    public let sensitivity: String?
    /// ISO-8601. The frontmatter `updated` when present, else the file's
    /// modification date, so a note edited outside CerebralHelm still sorts by
    /// when it actually changed. Nil only when neither is readable.
    public let updated: String?

    public init(
        path: String, title: String, noteID: String?, folder: String,
        project: String?, sensitivity: String?, updated: String?
    ) {
        self.path = path
        self.title = title
        self.noteID = noteID
        self.folder = folder
        self.project = project
        self.sensitivity = sensitivity
        self.updated = updated
    }
}

public struct NoteListRequest: Equatable, Sendable {
    /// Caps the returned entries; the outcome reports whether the cap truncated.
    public let limit: Int?

    public init(limit: Int?) {
        self.limit = limit
    }
}

public struct NoteListOutcome: Equatable, Sendable {
    /// The absolute path of the effective knowledge root the entries came from, so
    /// a caller can cite the source location without a second read channel.
    public let root: String
    /// Most recently updated first, then by path so equal timestamps stay stable.
    public let entries: [NoteListEntry]
    /// Every note found under the root, before any limit. A caller that asks for
    /// the five most recent notes still learns how many there are — a count that
    /// silently meant "as many as I asked for" would misdescribe the library.
    public let total: Int
    /// Whether the requested limit cut the listing short (`total > entries.count`).
    public let truncated: Bool

    public init(root: String, entries: [NoteListEntry], total: Int, truncated: Bool) {
        self.root = root
        self.entries = entries
        self.total = total
        self.truncated = truncated
    }
}

public struct NoteReadRequest: Equatable, Sendable {
    /// The note's root-relative path, as reported by ``NoteListEntry/path``.
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

/// One note's full content (NIC-162): its parsed frontmatter, its Markdown body,
/// and where it lives. Frontmatter is surfaced verbatim as parsed — including
/// keys CerebralHelm does not write — because the file is the source of truth.
public struct NoteReadOutcome: Equatable, Sendable {
    public let root: String
    public let path: String
    public let title: String
    public let noteID: String?
    public let frontmatter: [String: String]
    public let body: String
    public let updated: String?

    public init(
        root: String, path: String, title: String, noteID: String?,
        frontmatter: [String: String], body: String, updated: String?
    ) {
        self.root = root
        self.path = path
        self.title = title
        self.noteID = noteID
        self.frontmatter = frontmatter
        self.body = body
        self.updated = updated
    }
}

/// Where a note lives, resolved against the knowledge root (quick actions phase 5).
///
/// `absolutePath` is the only place in the note pipeline an absolute filesystem path
/// is produced, and it exists for exactly one consumer: the platform adapter that
/// hands a file to an editor. It is deliberately **not** carried across the bridge —
/// the web layer addresses notes by root-relative path, and a surface that never
/// learns absolute paths cannot ask for one outside the root.
public struct NoteLocation: Equatable, Sendable {
    /// The absolute path of the knowledge root the note was resolved against.
    public let root: String
    /// The note's root-relative path, forward-slashed.
    public let path: String
    public let absolutePath: String

    public init(root: String, path: String, absolutePath: String) {
        self.root = root
        self.path = path
        self.absolutePath = absolutePath
    }
}

/// Failures the knowledge service raises, mirroring the canonical knowledge
/// fixtures (PRD §13.2): a missing or read-only root, a collision with an existing
/// note, a write failure, or a note that cannot be read at the requested path.
public enum KnowledgeServiceError: Error, Equatable, Sendable {
    case rootUnavailable
    case rootReadOnly
    /// A note already exists at the target path; capture never overwrites (AC-44.3).
    case collision(String)
    case writeFailed(String)
    /// No readable note at the requested path (NIC-162). Also the answer to a path
    /// that resolves outside the knowledge root: a read never confirms or denies
    /// anything about the filesystem beyond the root.
    case noteNotFound(String)
}
