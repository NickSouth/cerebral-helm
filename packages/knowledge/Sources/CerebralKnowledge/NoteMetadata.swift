import Foundation
import CerebralContracts

/// A note before its system-managed metadata is completed. Optional fields are
/// filled with safe defaults by ``NoteMetadataNormalizer``; the durable capture
/// path (PRE-DATA-2) builds a draft from a capture request and normalizes it.
public struct NoteDraft: Equatable {
    public var id: String?
    public var title: String
    public var kind: String
    public var project: String?
    public var sensitivity: Sensitivity?
    public var cloudPolicy: CloudPolicy?
    public var status: CerebralHelmNoteMetadataStatus?
    public var reviewAfter: Date?

    public init(
        id: String? = nil,
        title: String,
        kind: String,
        project: String? = nil,
        sensitivity: Sensitivity? = nil,
        cloudPolicy: CloudPolicy? = nil,
        status: CerebralHelmNoteMetadataStatus? = nil,
        reviewAfter: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.project = project
        self.sensitivity = sensitivity
        self.cloudPolicy = cloudPolicy
        self.status = status
        self.reviewAfter = reviewAfter
    }
}

/// Completes a note's system-managed frontmatter with safe defaults (FR-KNW-05).
///
/// Absent optional fields degrade to safe values: `sensitivity` → private,
/// `status` → active, `id` → a file-safe slug of the title, `created`/`updated` →
/// the capture instant. `cloudPolicy` defaults to **deny** and is never defaulted
/// to `allow` (AC-43.3): an explicit `allow` remains a user choice the contract
/// permits, but the *absence* of a policy never grants cloud access.
public enum NoteMetadataNormalizer {
    /// The note-metadata contract version this normalizer emits.
    public static let schemaVersion = "1.0.0"

    public static func normalize(_ draft: NoteDraft, now: Date) -> CerebralHelmNoteMetadata {
        CerebralHelmNoteMetadata(
            cloudPolicy: draft.cloudPolicy ?? .deny,
            created: now,
            id: draft.id ?? NoteNaming.id(fromTitle: draft.title),
            kind: draft.kind,
            project: draft.project,
            reviewAfter: draft.reviewAfter,
            schemaVersion: schemaVersion,
            sensitivity: draft.sensitivity ?? .sensitivityPrivate,
            status: draft.status ?? .active,
            title: draft.title,
            updated: now
        )
    }
}
