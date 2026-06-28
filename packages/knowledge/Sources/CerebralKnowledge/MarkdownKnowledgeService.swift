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
    private let clock: any TimeSource

    public init(rootURL: URL, metadataStore: (any NoteMetadataStore)? = nil, clock: any TimeSource = SystemClock()) {
        self.rootURL = rootURL
        self.metadataStore = metadataStore
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

        // Metadata is rebuildable from the file, so its persistence is best-effort:
        // a failed row never loses the captured note.
        try? metadataStore?.upsert(Self.entry(for: metadata, path: relativePath))

        return NoteCaptureOutcome(noteID: metadata.id, path: relativePath, created: true)
    }

    public func search(_ request: NoteSearchRequest) async throws -> NoteSearchOutcome {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return NoteSearchOutcome(hits: [], truncated: false)
        }
        let query = request.query.lowercased()
        var hits: [NoteSearchHit] = []
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let (frontmatter, body) = FrontmatterCodec.parse(content)
            let relativePath = Self.relativePath(of: url, under: rootURL)
            let title = frontmatter["title"] ?? url.deletingPathExtension().lastPathComponent
            let haystack = "\(title)\n\(body)\n\(relativePath)".lowercased()
            guard query.isEmpty || haystack.contains(query) else { continue }
            hits.append(NoteSearchHit(
                noteID: frontmatter["id"] ?? url.deletingPathExtension().lastPathComponent,
                title: title,
                excerpt: Self.excerpt(body),
                path: relativePath,
                updated: frontmatter["updated"] ?? "",
                sensitivity: frontmatter["sensitivity"],
                freshness: nil
            ))
        }
        hits.sort { $0.path < $1.path }
        let limited = request.limit.map { Array(hits.prefix($0)) } ?? hits
        return NoteSearchOutcome(hits: limited, truncated: limited.count < hits.count)
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
