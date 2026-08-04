import Testing

import CerebralCore

/// Quick actions phase 5: deriving course folder names and note filenames.
///
/// These rules carry more weight than they look like they should: the folders on disk **are** the
/// course mapping, so a naming rule that is not deterministic would silently split one course into
/// two notebooks over a semester.

@Test("a course is named by its code, which is the part that survives a retitle")
func courseCodeIsPreferred() {
    // Canvas titles carry the term, the section and the full name — all of which change between
    // semesters while the code does not.
    #expect(
        CourseNaming.folderName(for: "STAT 240 - Introduction to Probability and Statistics (Fall 2026)")
            == "STAT 240"
    )
    #expect(CourseNaming.folderName(for: "CS260: Data Structures") == "CS 260")
    // Spacing and case are normalized, so the same course cannot produce two folders.
    #expect(CourseNaming.folderName(for: "stat240") == "STAT 240")
    #expect(CourseNaming.folderName(for: "  STAT   240  ") == "STAT 240")
}

@Test("an honours or section suffix is part of the code — two courses, two notebooks")
func courseCodeKeepsASuffix() {
    #expect(CourseNaming.courseCode(in: "MATH 131H Honors Calculus") == "MATH 131H")
    #expect(CourseNaming.courseCode(in: "MATH 131 Calculus") == "MATH 131")
    // Which is the point: they must not collapse into one folder.
    #expect(CourseNaming.folderName(for: "MATH 131H") != CourseNaming.folderName(for: "MATH 131"))
}

@Test("a course with no code keeps its name — a hand-added subject is still a course")
func courseWithoutACodeKeepsItsName() {
    // The `+ New course` case: a reading group, a self-study subject, anything not from Canvas.
    #expect(CourseNaming.folderName(for: "Reading group") == "Reading group")
    #expect(CourseNaming.courseCode(in: "Reading group") == nil)
    #expect(CourseNaming.courseCode(in: "Introduction to Statistics") == nil)
}

@Test("a four-digit year is never mistaken for a course code")
func yearsAreNotCourseCodes() {
    // Found by this test: without an EXACT three-digit rule, `Fall 2026` matched as `FALL 202` —
    // a truncated year that looks exactly like a course code, which would file a whole semester
    // under a folder named after the term.
    #expect(CourseNaming.courseCode(in: "Fall 2026 STAT 240") == "STAT 240")
    #expect(CourseNaming.courseCode(in: "Fall 2026") == nil)
    #expect(CourseNaming.courseCode(in: "Spring 2027 CS 260 Data Structures") == "CS 260")

    // The residual ambiguity, stated rather than pretended away: a word of 2-4 letters followed by
    // exactly three digits IS a course code as far as this rule can tell, so a title like
    // "Fall 240 students" would match. Distinguishing it needs a list of real subject codes, which
    // is a per-institution fact this does not have — and the failure is visible and correctable
    // (a folder with an odd name) rather than silent.
    #expect(CourseNaming.courseCode(in: "Fall 240 students") == "FALL 240")
}

@Test("a folder name can never describe two levels, or climb out of the school root")
func folderNamesAreSingleComponents() {
    // The name goes straight onto a path, so a separator must not survive as one. Escaping is not
    // enough — the only safe answer to "STAT/240" is a name that cannot be two components.
    for hostile in ["STAT/240", "STAT\\240", "../escape", "..", "./.", "  ..  "] {
        let name = CourseNaming.folderName(for: hostile)
        #expect(name?.contains("/") != true)
        #expect(name?.contains("\\") != true)
        #expect(name != "..")
        #expect(name?.hasPrefix(".") != true)
    }
    // A name that empties out is not a course at all.
    #expect(CourseNaming.folderName(for: "") == nil)
    #expect(CourseNaming.folderName(for: "   ") == nil)
    #expect(CourseNaming.folderName(for: "...") == nil)
}

@Test("note filenames are date-prefixed, so a course folder sorts chronologically by itself")
func noteFilenamesAreDatePrefixed() {
    #expect(
        CourseNaming.noteFilename(date: "2026-08-04", title: "Lecture 3 — Bayes")
            == "2026-08-04 Lecture 3 — Bayes.md"
    )
    // Sorting is the whole reason for the prefix: an alphabetical listing is chronological.
    let names = [
        CourseNaming.noteFilename(date: "2026-09-02", title: "Zeta"),
        CourseNaming.noteFilename(date: "2026-08-04", title: "Alpha")
    ].sorted()
    #expect(names.first?.hasPrefix("2026-08-04") == true)
    // A title that cannot name a file still produces one rather than failing the write.
    #expect(CourseNaming.noteFilename(date: "2026-08-04", title: "///") == "2026-08-04 note.md")
}
