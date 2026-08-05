import Foundation
import Testing

import CerebralCore
import CerebralShared
@testable import CerebralKnowledge

/// Quick actions phase 5: course notebooks over the durable Markdown.
///
/// The through-line is that **the folders are the mapping**: there is no stored course table, so a
/// course exists exactly when its folder does, and a course note is an ordinary note that the
/// existing note port can list, read and open without knowing what a course is.

private let t0 = Date(timeIntervalSince1970: 1_754_320_000) // 2026-08-04, locally

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-courses-\(UUID().uuidString)", isDirectory: true)
}

private func notebook(_ root: URL, at now: Date = t0) -> MarkdownCourseNotebook {
    MarkdownCourseNotebook(rootURL: root, clock: FixedClock(now))
}

private func makeRoot() throws -> URL {
    let root = temporaryRoot()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: - courses

@Test("an absent school folder is no courses, not a failure")
func coursesAreEmptyBeforeAnyExist() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try await notebook(root).courses().isEmpty)
}

@Test("a missing knowledge root is unavailable, not empty (FR-KNW-07)")
func coursesReportAMissingRoot() async throws {
    let root = temporaryRoot() // never created
    await #expect(throws: KnowledgeServiceError.rootUnavailable) {
        _ = try await notebook(root).courses()
    }
}

@Test("a folder made by hand in Obsidian is a course — no import, no rebuild")
func coursesReadTheFoldersThemselves() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    // Nothing here goes through the notebook: this is a user with Finder and Obsidian.
    let handMade = root.appendingPathComponent("areas/school-umass/PHIL 100", isDirectory: true)
    try FileManager.default.createDirectory(at: handMade, withIntermediateDirectories: true)
    try Data("# Lecture\n".utf8).write(to: handMade.appendingPathComponent("2026-08-01 Lecture.md"))

    let courses = try await notebook(root).courses()

    #expect(courses.count == 1)
    #expect(courses.first?.course == "PHIL 100")
    #expect(courses.first?.folder == "areas/school-umass/PHIL 100")
    #expect(courses.first?.noteCount == 1)
    #expect(courses.first?.updated != nil)
}

@Test("an empty course is a course — zero notes is a real answer")
func emptyCoursesAreListed() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try await notebook(root).ensure(course: "CS 260")

    let courses = try await notebook(root).courses()

    #expect(courses.map(\.course) == ["CS 260"])
    #expect(courses.first?.noteCount == 0)
    // No notes means no date. Reporting one would invent a fact about an empty folder.
    #expect(courses.first?.updated == nil)
}

@Test("only the course's own notes are counted, and only Markdown")
func courseNoteCountsIgnoreStrayFiles() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let course = try await notebook(root).ensure(course: "STAT 240")
    let folder = root.appendingPathComponent(course.folder, isDirectory: true)

    try Data("# One\n".utf8).write(to: folder.appendingPathComponent("2026-08-01 One.md"))
    // A PDF handout is not a note; a sub-folder is a sub-topic, counted as part of neither.
    try Data("%PDF".utf8).write(to: folder.appendingPathComponent("handout.pdf"))
    let nested = folder.appendingPathComponent("readings", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("# Two\n".utf8).write(to: nested.appendingPathComponent("2026-08-02 Two.md"))

    let courses = try await notebook(root).courses()
    #expect(courses.first(where: { $0.course == "STAT 240" })?.noteCount == 1)
}

// MARK: - ensure

@Test("minting a course is idempotent and never touches an existing folder's notes")
func ensureIsIdempotent() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try await notebook(root).ensure(course: "STAT 240 - Probability (Fall 2026)")
    let folder = root.appendingPathComponent(first.folder, isDirectory: true)
    try Data("# Kept\n".utf8).write(to: folder.appendingPathComponent("2026-08-01 Kept.md"))

    // The same course, named differently — the derived code makes them one folder.
    let second = try await notebook(root).ensure(course: "stat240")

    #expect(first.folder == second.folder)
    #expect(second.noteCount == 1)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("2026-08-01 Kept.md").path))
}

@Test("a course name that cannot name a folder is refused, not sanitized into something else")
func ensureRefusesUnusableNames() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    for unusable in ["", "   ", "...", "/"] {
        await #expect(throws: KnowledgeServiceError.self) {
            _ = try await notebook(root).ensure(course: unusable)
        }
    }
}

@Test("a course can never be minted outside the school root")
func ensureContainsTheFolder() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    // The caller names a COURSE, not a folder — a separator cannot buy a second path component.
    let folder = try await notebook(root).ensure(course: "../../escape")
    #expect(folder.folder.hasPrefix("areas/school-umass/"))
    #expect(!folder.folder.contains(".."))
    let escaped = root.deletingLastPathComponent().appendingPathComponent("escape")
    #expect(!FileManager.default.fileExists(atPath: escaped.path))
}

// MARK: - createNote

@Test("a created note is date-prefixed, templated, and lands in its course")
func createNoteWritesTheTemplate() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let outcome = try await notebook(root).createNote(
        course: "STAT 240 - Probability", title: "Lecture 3 — Bayes"
    )

    #expect(outcome.created)
    #expect(outcome.course == "STAT 240")
    let day = MarkdownCourseNotebook.day(t0)
    #expect(outcome.path == "areas/school-umass/STAT 240/\(day) Lecture 3 — Bayes.md")

    let content = try String(contentsOf: root.appendingPathComponent(outcome.path), encoding: .utf8)
    // Frontmatter the note port already understands, so a course note lists and reads like any other.
    #expect(content.contains("title: Lecture 3 — Bayes"))
    #expect(content.contains("course: STAT 240"))
    #expect(content.contains("tags: [course-note]"))
    // The H1 repeats the title so the note reads correctly with no frontmatter support at all.
    #expect(content.contains("# Lecture 3 — Bayes"))
    // Light structure: enough to start typing, generic across a lecture, a reading, a study session.
    #expect(content.contains("## Notes"))
    #expect(content.contains("## Questions"))
    #expect(content.contains("## Action items"))
}

@Test("taking a note is what creates the course — browsing one leaves nothing behind")
func createNoteMintsTheCourse() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try await notebook(root).courses().isEmpty)
    _ = try await notebook(root).createNote(course: "CS 260", title: "Week 1")

    let courses = try await notebook(root).courses()
    #expect(courses.map(\.course) == ["CS 260"])
    #expect(courses.first?.noteCount == 1)
}

@Test("a second note of the same title on the same day opens the first, never overwrites it")
func createNoteNeverOverwrites() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try await notebook(root).createNote(course: "STAT 240", title: "Lecture 3")
    // Someone typed into it between the two calls — that content must survive.
    let fileURL = root.appendingPathComponent(first.path)
    try Data("# Lecture 3\n\nmy own writing\n".utf8).write(to: fileURL)

    let second = try await notebook(root).createNote(course: "STAT 240", title: "Lecture 3")

    // Reported as NOT created: the caller must not tell the user it made a new note.
    #expect(!second.created)
    #expect(second.path == first.path)
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.contains("my own writing"))
}

@Test("a note needs a title, and a missing root fails the write rather than losing it silently")
func createNoteRefusesBadInput() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    await #expect(throws: KnowledgeServiceError.self) {
        _ = try await notebook(root).createNote(course: "STAT 240", title: "   ")
    }
}

@Test("a first note creates the vault, exactly as capturing a first note does")
func createNoteCreatesTheRoot() async throws {
    // Found by the composition test: `capture` builds the whole chain through its atomic write, so
    // a first note works on a fresh install. "Capture makes the root, taking a course note does
    // not" would be an inconsistency the user hits on day one.
    let root = temporaryRoot() // deliberately never created
    defer { try? FileManager.default.removeItem(at: root) }

    let outcome = try await notebook(root).createNote(course: "STAT 240", title: "Lecture 1")

    #expect(outcome.created)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(outcome.path).path))
    // Reading stays the asymmetric half: a missing root is unavailable, never "no courses".
    let gone = temporaryRoot()
    await #expect(throws: KnowledgeServiceError.rootUnavailable) {
        _ = try await notebook(gone).courses()
    }
}

@Test("a course note is an ordinary note — the note port lists and reads it unchanged")
func courseNotesAreOrdinaryNotes() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let created = try await notebook(root).createNote(course: "STAT 240", title: "Lecture 3")

    // The whole reason a course is just a folder: everything already built works on it.
    let knowledge = MarkdownKnowledgeService(rootURL: root, clock: FixedClock(t0))
    let listed = try await knowledge.list(NoteListRequest(limit: nil))
    let entry = try #require(listed.entries.first { $0.path == created.path })
    #expect(entry.title == "Lecture 3")
    #expect(entry.folder == "areas/school-umass/STAT 240")

    let read = try await knowledge.read(NoteReadRequest(path: created.path))
    #expect(read.frontmatter["course"] == "STAT 240")
    // And it can be handed to Obsidian by the same handle the picker uses.
    let located = try await knowledge.locate(NoteReadRequest(path: created.path))
    #expect(located.absolutePath.hasSuffix(created.path))
}
