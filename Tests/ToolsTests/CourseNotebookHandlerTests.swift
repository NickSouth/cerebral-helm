import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 5: the portable `course.list` and `course.note.create` handlers.

@Test("course.list reports the courses and where they came from")
func courseListHandlerHappyPath() async throws {
    let notebook = MockCourseNotebook(courses: ["STAT 240": ["a.md", "b.md"], "CS 260": []])
    let output = try await CourseListHandler(notebook: notebook).execute(input: Data("{}".utf8))
    let decoded = try CerebralHelmCourseListOutput(data: output)

    #expect(decoded.courseRoot == "areas/school-umass")
    #expect(decoded.courses.map(\.courseName) == ["CS 260", "STAT 240"])
    // Zero notes is a real answer, not an omission: a course can exist and be empty.
    #expect(decoded.courses.first(where: { $0.courseName == "CS 260" })?.courseNoteCount == 0)
    #expect(decoded.courses.first(where: { $0.courseName == "STAT 240" })?.courseNoteCount == 2)
    #expect(decoded.courses.first(where: { $0.courseName == "CS 260" })?.courseUpdated == nil)
}

@Test("course.list honours its cap and rejects input that does not decode")
func courseListHandlerCapsAndValidates() async throws {
    let notebook = MockCourseNotebook(courses: ["STAT 240": [], "CS 260": [], "PHIL 100": []])
    let handler = CourseListHandler(notebook: notebook)

    let output = try await handler.execute(input: Data(#"{"courseLimit":2}"#.utf8))
    #expect(try CerebralHelmCourseListOutput(data: output).courses.count == 2)

    do {
        _ = try await handler.execute(input: Data(#"{"courseLimit":"all"}"#.utf8))
        Issue.record("a non-integer cap must be rejected as invalid input")
    } catch ToolHandlerError.invalidInput {}
}

@Test("an unreadable knowledge root is structured, never an empty course list")
func courseListHandlerReportsMissingRoot() async throws {
    let notebook = MockCourseNotebook(rootAvailable: false)
    do {
        _ = try await CourseListHandler(notebook: notebook).execute(input: Data("{}".utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    // "No courses yet" and "your vault is gone" must never look the same.
    Issue.record("a missing root must surface as unavailable, not as zero courses")
}

@Test("course.note.create returns the path the note actually landed at")
func courseNoteCreateHandlerHappyPath() async throws {
    let notebook = MockCourseNotebook()
    let output = try await CourseNoteCreateHandler(notebook: notebook).execute(
        input: Data(#"{"noteCourse":"STAT 240 - Probability","noteTitle":"Lecture 3"}"#.utf8)
    )
    let decoded = try CerebralHelmCourseNoteCreateOutput(data: output)

    #expect(decoded.noteCreated)
    // The course as RESOLVED — the derived code, not the long title that was asked for.
    #expect(decoded.noteCourse == "STAT 240")
    #expect(decoded.notePath == "areas/school-umass/STAT 240/2026-08-04 Lecture 3.md")
}

@Test("the caller names a course, never a folder — a note cannot land outside the school root")
func courseNoteCreateHandlerContainsTheWrite() async throws {
    let notebook = MockCourseNotebook()
    let output = try await CourseNoteCreateHandler(notebook: notebook).execute(
        input: Data(#"{"noteCourse":"../../escape","noteTitle":"Anywhere"}"#.utf8)
    )
    let decoded = try CerebralHelmCourseNoteCreateOutput(data: output)

    #expect(decoded.notePath.hasPrefix("areas/school-umass/"))
    #expect(!decoded.notePath.contains(".."))
}

@Test("a repeat create reports created:false rather than claiming a new note")
func courseNoteCreateHandlerNeverOverwrites() async throws {
    let notebook = MockCourseNotebook()
    let handler = CourseNoteCreateHandler(notebook: notebook)
    let input = Data(#"{"noteCourse":"STAT 240","noteTitle":"Lecture 3"}"#.utf8)

    _ = try await handler.execute(input: input)
    let second = try CerebralHelmCourseNoteCreateOutput(data: try await handler.execute(input: input))

    #expect(!second.noteCreated)
}

@Test("course.note.create rejects input that does not decode against its contract")
func courseNoteCreateHandlerRejectsMalformedInput() async throws {
    let handler = CourseNoteCreateHandler(notebook: MockCourseNotebook())
    for bad in [#"{"noteCourse":"STAT 240"}"#, #"{"noteTitle":"Lecture"}"#, #"{}"#] {
        do {
            _ = try await handler.execute(input: Data(bad.utf8))
            Issue.record("\(bad) must be rejected as invalid input")
        } catch ToolHandlerError.invalidInput {}
    }
}
