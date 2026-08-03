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
    /// The absolute knowledge root this service reads and writes — the effective
    /// root after any user re-point (NIC-138). Exposed so a caller can cite the
    /// source location without walking the tree to find it out.
    public var rootPath: String { rootURL.path }
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
    ///
    /// Returns the number of notes indexed, so a caller can report what the
    /// rebuild actually covered rather than a bare "done" (NIC-163). Never writes
    /// to the Markdown: only the derived index is touched.
    @discardableResult
    public func rebuild() throws -> Int {
        guard let searchIndex else { return 0 }
        try searchIndex.deleteAll()
        var indexed = 0
        for url in Self.markdownFiles(under: rootURL) {
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
            indexed += 1
        }
        return indexed
    }

    // MARK: - Library reads (NIC-162)

    /// Lists the notes under the root by walking the Markdown itself (FR-KNW-01):
    /// the files are the source of truth, and the derived index only knows what
    /// CerebralHelm captured — so a note authored in another editor appears here
    /// immediately, before any rebuild.
    ///
    /// An empty root is an empty list, not a failure; a *missing* root is
    /// ``KnowledgeServiceError/rootUnavailable`` so the caller can say so honestly
    /// instead of showing an empty knowledge base (FR-KNW-07).
    public func list(_ request: NoteListRequest) async throws -> NoteListOutcome {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw KnowledgeServiceError.rootUnavailable
        }

        let sorted = Self.markdownFiles(under: rootURL)
            .map { Self.entry(at: $0, under: rootURL) }
            // Most recently changed first; path breaks ties so equal (or absent)
            // timestamps still produce a stable order.
            .sorted { left, right in
                if left.changed != right.changed {
                    return (left.changed ?? .distantPast) > (right.changed ?? .distantPast)
                }
                return left.entry.path < right.entry.path
            }
            .map(\.entry)

        let limited = request.limit.map { Array(sorted.prefix($0)) } ?? sorted
        return NoteListOutcome(
            root: rootURL.path, entries: limited, total: sorted.count,
            truncated: limited.count < sorted.count
        )
    }

    /// Reads one note by its root-relative path (NIC-162), returning its parsed
    /// frontmatter and Markdown body.
    ///
    /// The path is resolved against the root and the *resolved* location must sit
    /// inside it, so neither `..` traversal nor a symlink pointing outward can read
    /// a file the knowledge root does not contain. A refused path and a missing
    /// note are the same answer — this never reports what exists outside the root.
    public func read(_ request: NoteReadRequest) async throws -> NoteReadOutcome {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw KnowledgeServiceError.rootUnavailable
        }
        let notFound = KnowledgeServiceError.noteNotFound(
            "No note at \(request.path) in the knowledge root."
        )

        let components = request.path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
        // Only Markdown is a note, and no component may climb out of the root.
        guard
            let filename = components.last,
            filename.hasSuffix(".md"),
            !components.contains("..")
        else { throw notFound }

        let fileURL = components.reduce(rootURL) { $0.appendingPathComponent($1) }
        // Resolve both sides: the root itself is often reached through a symlink
        // (macOS `/var` → `/private/var`), so comparing unresolved paths would
        // reject legitimate reads while still admitting a symlinked escape.
        let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let base = rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(base.path + "/") else { throw notFound }
        guard let content = try? String(contentsOf: resolved, encoding: .utf8) else { throw notFound }

        let (frontmatter, body) = FrontmatterCodec.parse(content)
        let relativePath = Self.relativePath(of: fileURL, under: rootURL)
        return NoteReadOutcome(
            root: rootURL.path,
            path: relativePath,
            title: Self.title(frontmatter: frontmatter, filename: filename),
            noteID: frontmatter["id"],
            frontmatter: frontmatter,
            body: body,
            updated: Self.updated(frontmatter: frontmatter, url: resolved).iso
        )
    }

    /// Every Markdown file under `root`, or none when the root is absent.
    ///
    /// Hidden files and directories are skipped, so an editor's own state never
    /// becomes a note: Obsidian keeps its configuration in `.obsidian/` and its
    /// deletions in `.trash/`, and a trashed note is not a note.
    private static func markdownFiles(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "md" { files.append(url) }
        }
        return files
    }

    /// Projects one file into a listing entry, carrying the date it sorts by.
    private static func entry(at url: URL, under root: URL) -> (entry: NoteListEntry, changed: Date?) {
        let frontmatter = (try? String(contentsOf: url, encoding: .utf8))
            .map { FrontmatterCodec.parse($0).frontmatter } ?? [:]
        let relativePath = relativePath(of: url, under: root)
        let folder = relativePath.contains("/")
            ? String(relativePath[relativePath.startIndex..<relativePath.lastIndex(of: "/")!])
            : ""
        let changed = updated(frontmatter: frontmatter, url: url)

        return (
            NoteListEntry(
                path: relativePath,
                title: title(frontmatter: frontmatter, filename: url.lastPathComponent),
                noteID: frontmatter["id"],
                folder: folder,
                project: frontmatter["project"] ?? project(inFolder: folder),
                sensitivity: frontmatter["sensitivity"],
                updated: changed.iso
            ),
            changed.date
        )
    }

    /// A note's title: its frontmatter title, else the filename — which is the
    /// title for anything authored outside CerebralHelm.
    private static func title(frontmatter: [String: String], filename: String) -> String {
        if let title = frontmatter["title"], !title.isEmpty { return title }
        return filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
    }

    /// When a note last changed: its frontmatter `updated` if it declares one,
    /// else the file's modification date — an edit made in another editor moves
    /// the file's date but not the frontmatter, and recency should reflect it.
    private static func updated(frontmatter: [String: String], url: URL) -> (iso: String?, date: Date?) {
        if let declared = frontmatter["updated"], let parsed = parseISO(declared) {
            return (declared, parsed)
        }
        guard
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return (nil, nil) }
        return (iso(modified), modified)
    }

    /// The project a note belongs to by position, for a note whose frontmatter
    /// does not name one — capture files into `projects/<project>/`, so the
    /// hierarchy already says it.
    private static func project(inFolder folder: String) -> String? {
        let components = folder.split(separator: "/").map(String.init)
        guard components.count >= 2, components[0] == "projects" else { return nil }
        return components[1]
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
