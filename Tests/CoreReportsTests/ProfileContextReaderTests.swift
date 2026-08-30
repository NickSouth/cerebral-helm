import Foundation
import Testing
@testable import CerebralCore

/// NIC-251: the ~1–2K tokens that make a brief personal.
///
/// The measured effect is large and cheap — roughly a hundred tokens of profile turned a recitation
/// of weather metrics into a suggestion, with deliberation off and at no latency cost. What these
/// tests protect is the discipline around it: only the profile folder, only what policy admits,
/// whole notes only, and a stable order so the prompt's cache prefix does not move.

// MARK: - A scripted vault

private struct Note {
    let path: String
    let title: String
    let body: String
    var folder: String = "profile"
    var sensitivity: String? = "sensitive"
    var cloudPolicy: String? = "deny"
    var updated: String?
}

private struct ScriptedKnowledge: KnowledgeService {
    var notes: [Note] = []
    var listFailure: KnowledgeServiceError?
    var unreadablePaths: Set<String> = []

    func list(_ request: NoteListRequest) async throws -> NoteListOutcome {
        if let listFailure { throw listFailure }
        let entries = notes.map {
            NoteListEntry(
                path: $0.path, title: $0.title, noteID: $0.path, folder: $0.folder,
                project: nil, sensitivity: $0.sensitivity, updated: $0.updated
            )
        }
        return NoteListOutcome(root: "/vault", entries: entries, total: entries.count, truncated: false)
    }

    func read(_ request: NoteReadRequest) async throws -> NoteReadOutcome {
        guard !unreadablePaths.contains(request.path),
              let note = notes.first(where: { $0.path == request.path })
        else { throw KnowledgeServiceError.noteNotFound(request.path) }

        var frontmatter: [String: String] = [:]
        if let sensitivity = note.sensitivity { frontmatter["sensitivity"] = sensitivity }
        if let cloudPolicy = note.cloudPolicy { frontmatter["cloudPolicy"] = cloudPolicy }
        return NoteReadOutcome(
            root: "/vault", path: note.path, title: note.title, noteID: note.path,
            frontmatter: frontmatter, body: note.body, updated: note.updated
        )
    }

    func capture(_ request: NoteCaptureRequest) async throws -> NoteCaptureOutcome {
        throw KnowledgeServiceError.rootReadOnly
    }
    func search(_ request: NoteSearchRequest) async throws -> NoteSearchOutcome {
        NoteSearchOutcome(hits: [], truncated: false)
    }
    func locate(_ request: NoteReadRequest) async throws -> NoteLocation {
        NoteLocation(root: "/vault", path: request.path, absolutePath: "/vault/\(request.path)")
    }
}

private func read(
    _ notes: [Note],
    destination: ModelDestination = .local,
    unreadable: Set<String> = [],
    listFailure: KnowledgeServiceError? = nil
) async throws -> String? {
    try await ProfileContextReader(
        knowledge: ScriptedKnowledge(notes: notes, listFailure: listFailure, unreadablePaths: unreadable),
        destination: destination
    ).read()
}

private let aboutMe = Note(
    path: "profile/about-me.md",
    title: "About Me",
    body: "Location: New England. Golfs whenever the weather allows.",
    updated: "2026-08-01T00:00:00Z"
)

// MARK: - Scope

@Test("only the profile folder is read")
func onlyProfileNotesAreIncluded() async throws {
    // The rest of the vault is phase 3's problem: retrieval over a corpus is a different mechanism
    // from including four short notes wholesale, and mixing them would put a meeting note from
    // March into a morning brief.
    let context = try #require(await read([
        aboutMe,
        Note(path: "inbox/idea.md", title: "Idea", body: "A thought.", folder: "inbox"),
        Note(path: "projects/atlas.md", title: "Atlas", body: "Ship it.", folder: "projects")
    ]))

    #expect(context.contains("New England"))
    #expect(!context.contains("A thought."))
    #expect(!context.contains("Ship it."))
}

@Test("an empty profile folder is nothing, not an empty string")
func emptyProfileIsNil() async throws {
    // Nil rather than "": an empty value is a fact a composer told to use what it is given would
    // dutifully describe, and there is nothing here to describe.
    #expect(try await read([]) == nil)
    #expect(try await read([Note(path: "inbox/x.md", title: "X", body: "y", folder: "inbox")]) == nil)
    // A note whose body is only whitespace contributes nothing and does not create a section.
    #expect(try await read([Note(path: "profile/blank.md", title: "Blank", body: "   \n\n  ")]) == nil)
}

// MARK: - Policy

@Test("a secret profile note never reaches the model, and is never even read")
func secretNotesAreExcludedBeforeReading() async throws {
    // Checked on the LISTING, where sensitivity is already available — so the body of a secret note
    // is not loaded and then discarded, it is never loaded. The profile README tells the user to
    // split health and finances into their own notes precisely so this lever has something to act on.
    let context = try await read(
        [
            aboutMe,
            Note(path: "profile/health.md", title: "Health", body: "Diagnosis details.", sensitivity: "secret")
        ],
        unreadable: ["profile/health.md"]
    )

    // `unreadable` would make the read THROW if it happened; the note is excluded before that.
    #expect(context?.contains("New England") == true)
    #expect(context?.contains("Diagnosis") == false)
}

@Test("locally, a deny profile is exactly what gets used")
func denyIsUsedLocally() async throws {
    // Profile notes default to `cloudPolicy: deny`, and the brief is the surface they exist for. A
    // filter that excluded them locally would delete the feature it is protecting.
    let context = try #require(await read([aboutMe], destination: .local))
    #expect(context.contains("New England"))
}

@Test("bound for a cloud provider, the same profile is withheld")
func denyIsWithheldFromCloud() async throws {
    #expect(try await read([aboutMe], destination: .cloud) == nil)

    // Only an explicit allow survives the trip.
    var shareable = aboutMe
    shareable.cloudPolicy = "allow"
    #expect(try await read([shareable], destination: .cloud) != nil)
}

// MARK: - Shape and budget

@Test("each note is a titled section, so facts stay grouped")
func notesAreTitledSections() async throws {
    let context = try #require(await read([
        aboutMe,
        Note(path: "profile/work.md", title: "Work", body: "Building CerebralHelm.", updated: "2026-07-01T00:00:00Z")
    ]))

    #expect(context.contains("## About Me"))
    #expect(context.contains("## Work"))
    // "Health" and "Work" read very differently as an undifferentiated run of sentences.
    #expect(context.contains("\n\n"))
}

@Test("the freshest notes are kept when the budget forces a choice, and whole ones")
func budgetDropsWholeStaleNotes() async throws {
    let long = String(repeating: "detail. ", count: ProfileContextReader.tokenBudget)
    let context = try #require(await read([
        Note(path: "profile/fresh.md", title: "Fresh", body: "Current focus: shipping the brief.",
             updated: "2026-08-20T00:00:00Z"),
        Note(path: "profile/stale.md", title: "Stale", body: long, updated: "2020-01-01T00:00:00Z")
    ]))

    // Freshest first: a recently updated profile note reflects current reality, which is what makes
    // a brief timely.
    #expect(context.contains("Current focus"))
    // Whole notes only. A profile cut mid-sentence is worse than a shorter one — half of "he golfs
    // whenever the weather allows" is a different claim, and the model cannot tell it was cut.
    #expect(!context.contains("detail."))
}

@Test("a single note larger than the budget is still included rather than losing the profile")
func oversizeSoleNoteIsKept() async throws {
    // The ceiling is a discipline, not a limit. Dropping the only profile note because it is long
    // would trade the whole feature for a number that was a judgement in the first place.
    let long = String(repeating: "detail. ", count: ProfileContextReader.tokenBudget)
    #expect(try await read([Note(path: "profile/big.md", title: "Big", body: long)]) != nil)
}

@Test("the same vault renders the same context every time")
func orderingIsStable() async throws {
    // Undated notes tie, and a tie broken by dictionary order would move between runs — quietly
    // changing the prompt prefix and costing a cache measured at 98.7% in steady state.
    let notes = [
        Note(path: "profile/c.md", title: "C", body: "Third."),
        Note(path: "profile/a.md", title: "A", body: "First."),
        Note(path: "profile/b.md", title: "B", body: "Second.")
    ]

    let first = try #require(await read(notes))
    let second = try #require(await read(notes.reversed()))
    #expect(first == second)
    #expect(first.range(of: "First.")!.lowerBound < first.range(of: "Second.")!.lowerBound)
}

// MARK: - Failures

@Test("one unreadable note does not cost the whole profile")
func oneUnreadableNoteIsSkipped() async throws {
    let context = try #require(await read(
        [aboutMe, Note(path: "profile/gone.md", title: "Gone", body: "...")],
        unreadable: ["profile/gone.md"]
    ))

    // The others still describe the person.
    #expect(context.contains("New England"))
}

@Test("an unreadable vault throws rather than reporting an empty profile")
func unreadableVaultThrows() async {
    // "There is no profile" and "the vault is gone" are different facts, and the assembler renders
    // them differently — a ready-but-empty section against an honest unavailable one.
    await #expect(throws: KnowledgeServiceError.rootUnavailable) {
        try await read([aboutMe], listFailure: .rootUnavailable)
    }
}
