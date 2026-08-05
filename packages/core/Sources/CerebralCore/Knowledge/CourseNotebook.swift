/// Course notebooks (quick actions phase 5): the `take-notes` action's durable side.
///
/// A **thin layer over the knowledge root**, not a second knowledge system. A course is a folder
/// of Markdown under the school root, and a course note is an ordinary note — so everything the
/// note port already does (listing, searching, reading, opening in Obsidian) works on them without
/// knowing what a course is.
///
/// **The folders on disk are the mapping.** There is deliberately no stored course → folder table:
/// the folder is derived from the course's *code*, which is stable across the title changes Canvas
/// makes, and the folder's existence is what makes a course known. That follows the repository's
/// durable-state rule — the Markdown is the source of truth and everything else is rebuildable —
/// and it means a vault copied to another machine brings its courses with it.
///
/// The consequence, accepted knowingly: if a course's *code* ever changes, the next note lands in a
/// new folder and the old one keeps its notes. Nothing is orphaned — a folder with notes is still
/// listed as a course, so last term's material stays reachable — but they are two entries.
public protocol CourseNotebook: Sendable {
    /// Where course folders live, root-relative (`areas/school-umass`).
    ///
    /// Exposed so a surface can say where courses came from without knowing the convention — the
    /// same reason ``NoteListOutcome/root`` exists. A property rather than a per-call result
    /// because it is a fact about the notebook, not about any one read.
    var schoolFolder: String { get }

    /// The courses that exist on disk, most recently written first.
    ///
    /// Canvas is *not* consulted here: this reports what the vault actually contains, and the
    /// surface merges it with the live course list. Keeping the two apart is what lets a course
    /// from a finished semester stay openable after Canvas has stopped listing it.
    func courses() async throws -> [CourseFolder]

    /// The folder for a course, creating it if this is the first time it is used.
    ///
    /// Idempotent, and never destructive: an existing folder is returned untouched. The folder
    /// name is **derived here**, never supplied by the caller — a caller-chosen folder would make
    /// the destination an argument, which is precisely what the knowledge root's containment rule
    /// exists to prevent.
    func ensure(course: String) async throws -> CourseFolder

    /// Creates one note in a course, from the standard template, and returns where it landed.
    ///
    /// Mints the course folder on the way if it does not exist yet — so taking a note is the act
    /// that brings a course into being, and browsing one never leaves an empty folder behind.
    func createNote(course: String, title: String) async throws -> CourseNoteOutcome
}

/// One course's folder under the school root.
public struct CourseFolder: Equatable, Sendable {
    /// The course as it is displayed and addressed — the derived code (`STAT 240`) where the source
    /// carried one, else the cleaned-up name. It is also the folder's last path component.
    public let course: String
    /// Root-relative, forward-slashed (`areas/school-umass/STAT 240`), so it addresses the folder
    /// the same way ``NoteListEntry/folder`` does and can be compared to one directly.
    public let folder: String
    /// How many notes the folder holds. Zero is a real answer: a course can exist and be empty.
    public let noteCount: Int
    /// ISO-8601 of the most recently changed note in the folder, or nil when it holds none.
    public let updated: String?

    public init(course: String, folder: String, noteCount: Int, updated: String?) {
        self.course = course
        self.folder = folder
        self.noteCount = noteCount
        self.updated = updated
    }
}

/// Where a newly created course note landed.
public struct CourseNoteOutcome: Equatable, Sendable {
    public let course: String
    /// The note's root-relative path — the same handle `note.open` takes, so the caller can open
    /// what it just created without deriving a path of its own.
    public let path: String
    public let title: String
    /// False when a note of that name already existed for that day and was returned instead of
    /// being overwritten. Creating a note must never clobber one.
    public let created: Bool

    public init(course: String, path: String, title: String, created: Bool) {
        self.course = course
        self.path = path
        self.title = title
        self.created = created
    }
}

/// Derives file-safe course folder names and note filenames (quick actions phase 5).
///
/// Pure and deterministic: the same course always names the same folder, on every machine and in
/// every session. That is what lets the folders on disk *be* the course mapping.
public enum CourseNaming {
    /// The folder name for a course.
    ///
    /// Prefers the **course code** when the source carries one, because that is the stable part.
    /// Canvas titles a course `STAT 240 - Introduction to Probability and Statistics (Fall 2026)`,
    /// and the semester, the section and the wording all change between terms while `STAT 240`
    /// does not. A course with no recognizable code keeps its cleaned-up name, which is what a
    /// hand-added course (a reading group, a self-study subject) will normally be.
    ///
    /// Returns nil when nothing usable survives — a folder named after nothing is not a course.
    public static func folderName(for course: String) -> String? {
        let collapsed = course.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        let candidate = courseCode(in: collapsed) ?? collapsed
        return sanitize(candidate)
    }

    /// The `SUBJ 123` style code inside a course title, normalized to one space.
    ///
    /// Scanned rather than regex-matched so the rule is readable and has no engine to disagree
    /// with: two to four letters, an optional space, three digits, and an optional trailing letter
    /// (`CS 260`, `STAT240`, `MATH 131H`). The letters must start a word, so the `240` in
    /// "Fall 240 students" cannot be captured by the tail of another word.
    public static func courseCode(in title: String) -> String? {
        let characters = Array(title)
        var index = 0
        while index < characters.count {
            // Only start at a word boundary.
            let atWordStart = index == 0 || !characters[index - 1].isLetter
                && !characters[index - 1].isNumber
            guard atWordStart, characters[index].isLetter else {
                index += 1
                continue
            }
            var cursor = index
            var letters = ""
            while cursor < characters.count, characters[cursor].isLetter, letters.count < 4 {
                letters.append(characters[cursor])
                cursor += 1
            }
            guard letters.count >= 2, !(cursor < characters.count && characters[cursor].isLetter) else {
                index = cursor + 1
                continue
            }
            var spaced = cursor
            if spaced < characters.count, characters[spaced] == " " { spaced += 1 }
            var digits = ""
            var digitCursor = spaced
            while digitCursor < characters.count, characters[digitCursor].isNumber, digits.count < 3 {
                digits.append(characters[digitCursor])
                digitCursor += 1
            }
            // EXACTLY three digits. Without this, `Fall 2026 STAT 240` matches `FALL 202` — a
            // four-digit year truncated into a plausible-looking course code, which would file a
            // whole semester under the wrong folder.
            let exactlyThree = digits.count == 3
                && (digitCursor >= characters.count || !characters[digitCursor].isNumber)
            if exactlyThree {
                var code = "\(letters.uppercased()) \(digits)"
                // An honors/section suffix is part of the code — MATH 131 and MATH 131H are
                // different courses and must not share a notebook.
                if digitCursor < characters.count, characters[digitCursor].isLetter,
                   digitCursor + 1 >= characters.count || !characters[digitCursor + 1].isLetter {
                    code += String(characters[digitCursor]).uppercased()
                }
                return code
            }
            index = cursor + 1
        }
        return nil
    }

    /// Strips everything a folder name must not carry, keeping it recognizable.
    ///
    /// Path separators, `..`, leading dots and control characters are removed rather than escaped:
    /// this names a folder inside a fixed root, and the only safe answer to "STAT/240" is a name
    /// that cannot describe two levels. A name that empties out returns nil.
    public static func sanitize(_ name: String) -> String? {
        let cleaned = String(name.map { character -> Character in
            if character == "/" || character == "\\" || character == ":" { return "-" }
            if character.isNewline || character.unicodeScalars.contains(where: { $0.value < 32 }) {
                return " "
            }
            return character
        })
        let collapsed = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        // Trimmed without Foundation: this file stays importable wherever Core is.
        let trimmed = collapsed.drop(while: { ". -".contains($0) })
            .reversed().drop(while: { ". -".contains($0) }).reversed()
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    /// The filename for a note, date-prefixed so a course folder sorts chronologically by itself.
    ///
    /// Owner decision: after a semester, "in the order I wrote them" is what you want from a
    /// notebook, and a filename prefix gives that in every tool — Obsidian's sidebar, Finder, and
    /// `ls` — rather than only where a date field is indexed. The typed title stays the heading.
    public static func noteFilename(date: String, title: String) -> String {
        let slug = sanitize(title) ?? "note"
        return "\(date) \(slug).md"
    }
}
