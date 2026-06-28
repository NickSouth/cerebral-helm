import Foundation
import CerebralContracts
import CerebralCore
import CerebralShared

/// Durable ``KnowledgeService`` backed by Markdown files (FR-KNW-01/02, NFR-06).
///
/// Capture writes a complete note atomically (temp file + atomic replace) into the
/// knowledge hierarchy and records its rebuildable metadata. The Markdown file is
/// the source of truth; the metadata row is best-effort because it can be rebuilt
/// from the file (FR-KNW-06). Search is a direct file scan for the MVP — the
/// rebuildable derived index is PRE-DATA-3.
public struct MarkdownKnowledgeService: KnowledgeService {
    private let rootURL: URL
    private let metadataStore: (any NoteMetadataStore)?
    private let searchIndex: (any NoteSearchIndex)?
    private let clock: any TimeSource

    public init(
        rootURL: URL,
        metadataStore: (any NoteMetadataStore)? = nil,
        searchIndex: (any NoteSearchIndex)? = nil,
        clock: any TimeSource = SystemClock()
    ) {
        self.rootURL = rootURL
        self.metadataStore = metadataStore
        self.searchIndex = searchIndex
        self.clock = clock
    }

    public func capture(_ request: NoteCaptureRequest) async throws -> NoteCaptureOutcome {
        let now = clock.now()
        let draft = NoteDraft(
            id: NoteNaming.captureID(fromTitle: request.title, at: now),
            title: request.title,
            kind: request.kind,
            project: request.project,
            sensitivity: request.sensitivity.flatMap(Sensitivity.init(rawValue:))
        )
        let metadata = NoteMetadataNormalizer.normalize(draft, now: now)
        let components = Self.folderComponents(for: metadata) + [NoteNaming.filename(forID: metadata.id)]
        let relativePath = components.joined(separator: "/")
        let fileURL = components.reduce(rootURL) { $0.appendingPathComponent($1) }

        // Capture never overwrites an existing note (AC-44.3).
        if FileManager.default.fileExists(atPath: fileURL.path) {
            throw KnowledgeServiceError.collision("A note already exists at \(relativePath).")
        }

        try Self.atomicWrite(FrontmatterCodec.emit(metadata: metadata, body: request.body), to: fileURL)

        // Success requires the Markdown source to exist (AC-44.2).
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KnowledgeServiceError.writeFailed("The note was not present after writing.")
        }

        // Metadata and the search index are rebuildable from the file, so their
        // persistence is best-effort: a failed row never loses the captured note,
        // and a rebuild reconstructs them. Indexing here makes the note findable
        // immediately (AC-45.1).
        try? metadataStore?.upsert(Self.entry(for: metadata, path: relativePath))
        try? searchIndex?.upsert(Self.indexEntry(for: metadata, body: request.body, path: relativePath))

        return NoteCaptureOutcome(noteID: metadata.id, path: relativePath, created: true)
    }

    public func search(_ request: NoteSearchRequest) async throws -> NoteSearchOutcome {
        guard let searchIndex else { return NoteSearchOutcome(hits: [], truncated: false) }
        let now = clock.now()
        let hits = try searchIndex.matches(query: request.query).map { Self.hit(from: $0, now: now) }
        let limited = request.limit.map { Array(hits.prefix($0)) } ?? hits
        return NoteSearchOutcome(hits: limited, truncated: limited.count < hits.count)
    }

    /// Rebuilds the search index from the Markdown files on disk (FR-KNW-06): the
    /// derived index is dropped and reconstructed from the source of truth, so
    /// deleting it and rebuilding preserves results (AC-45.3).
    public func rebuild() throws {
        guard let searchIndex else { return }
        try searchIndex.deleteAll()
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let (frontmatter, body) = FrontmatterCodec.parse(content)
            let fallbackID = url.deletingPathExtension().lastPathComponent
            try searchIndex.upsert(NoteSearchIndexEntry(
                noteID: frontmatter["id"] ?? fallbackID,
                path: Self.relativePath(of: url, under: rootURL),
                title: frontmatter["title"],
                body: body,
                sensitivity: frontmatter["sensitivity"],
                updated: frontmatter["updated"].flatMap(Self.parseISO),
                reviewAfter: frontmatter["reviewAfter"].flatMap(Self.parseISO)
            ))
        }
    }

    // MARK: - Paths

    private static func folderComponents(for metadata: CerebralHelmNoteMetadata) -> [String] {
        if let project = metadata.project, !project.isEmpty { return ["projects", project] }
        return ["inbox"]
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        var relative = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
        relative = relative.replacingOccurrences(of: "\\", with: "/")
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    private static func excerpt(_ body: String, limit: Int = 160) -> String {
        let flattened = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count <= limit ? flattened : String(flattened.prefix(limit)) + "…"
    }

    private static func entry(for metadata: CerebralHelmNoteMetadata, path: String) -> NoteMetadataEntry {
        NoteMetadataEntry(
            noteID: metadata.id, path: path, title: metadata.title, kind: metadata.kind,
            project: metadata.project, sensitivity: metadata.sensitivity.rawValue,
            cloudPolicy: metadata.cloudPolicy.rawValue, status: metadata.status.rawValue,
            created: metadata.created, updated: metadata.updated, reviewAfter: metadata.reviewAfter
        )
    }

    private static func indexEntry(for metadata: CerebralHelmNoteMetadata, body: String, path: String) -> NoteSearchIndexEntry {
        NoteSearchIndexEntry(
            noteID: metadata.id, path: path, title: metadata.title, body: body,
            sensitivity: metadata.sensitivity.rawValue, updated: metadata.updated, reviewAfter: metadata.reviewAfter
        )
    }

    // MARK: - Hits

    private static func hit(from entry: NoteSearchIndexEntry, now: Date) -> NoteSearchHit {
        NoteSearchHit(
            noteID: entry.noteID,
            title: entry.title ?? entry.noteID,
            excerpt: excerpt(entry.body ?? ""),
            path: entry.path, // every result cites its source path (AC-45.2)
            updated: entry.updated.map(iso) ?? "",
            sensitivity: entry.sensitivity,
            freshness: freshness(reviewAfter: entry.reviewAfter, now: now)
        )
    }

    /// Derives freshness from the review boundary: no boundary is `unknown`, a
    /// passed boundary is `stale`, otherwise `fresh`.
    private static func freshness(reviewAfter: Date?, now: Date) -> String {
        guard let reviewAfter else { return Freshness.unknown.rawValue }
        return now >= reviewAfter ? Freshness.stale.rawValue : Freshness.fresh.rawValue
    }

    private static func iso(_ date: Date) -> String {
        ISO8601Timestamp.string(from: date)
    }

    private static func parseISO(_ string: String) -> Date? {
        ISO8601Timestamp.date(from: string)
    }

    // MARK: - Atomic write

    private static func atomicWrite(_ content: String, to fileURL: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // `.atomic` writes a temp file then replaces, so an interrupted write
            // never leaves a partial or corrupt note (AC-44.1, NFR-06).
            try Data(content.utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw classify(error)
        }
    }

    /// Maps a filesystem error to a structured ``KnowledgeServiceError`` (AC-44.3).
    /// Exposed for deterministic testing of the mapping.
    static func classify(_ error: Error) -> KnowledgeServiceError {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return .writeFailed(error.localizedDescription)
        }
        switch nsError.code {
        case CocoaError.fileWriteNoPermission.rawValue:
            return .rootReadOnly
        case CocoaError.fileNoSuchFile.rawValue, CocoaError.fileWriteInvalidFileName.rawValue:
            return .rootUnavailable
        default:
            return .writeFailed(nsError.localizedDescription)
        }
    }
}
