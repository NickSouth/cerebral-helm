import Foundation
import CerebralCore
import CerebralShared

/// Course notebooks over the durable Markdown (quick actions phase 5).
///
/// A course is a folder under the school root and a course note is an ordinary Markdown note, so
/// this deliberately owns almost nothing: it names folders, writes one templated file, and reads
/// the directory back. Listing, searching, reading and opening those notes are already the note
/// port's job and stay there.
///
/// **Nothing here is a second source of truth.** The folders *are* the course list, so a vault
/// moved to another machine brings its courses along, and a course deleted in Finder is gone
/// because that is what deleting a folder means.
public struct MarkdownCourseNotebook: CourseNotebook {
    /// Where course folders live, root-relative. Owner decision (2026-08-04): under the existing
    /// `areas/school-umass.md`, which Obsidian then treats as the folder's index note — the
    /// standard folder-note pattern — so PARA stays intact and all school material sits together.
    ///
    /// A constructor parameter rather than a constant so a second school, or a rename, is a
    /// composition change rather than an edit here. There is no setting for it yet; when one is
    /// wanted, it binds at the same place the root does.
    public static let defaultSchoolFolder = "areas/school-umass"

    private let rootURL: URL
    public let schoolFolder: String
    private let clock: any TimeSource

    public init(
        rootURL: URL,
        schoolFolder: String = MarkdownCourseNotebook.defaultSchoolFolder,
        clock: any TimeSource = SystemClock()
    ) {
        self.rootURL = rootURL
        self.schoolFolder = schoolFolder
        self.clock = clock
    }

    /// The school root as a URL. Not created on read — an absent folder means no courses yet,
    /// which is a true answer and not something a listing should fix by writing.
    private var schoolURL: URL {
        schoolFolder.split(separator: "/").map(String.init).reduce(rootURL) {
            $0.appendingPathComponent($1)
        }
    }

    public func courses() async throws -> [CourseFolder] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            throw KnowledgeServiceError.rootUnavailable
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: schoolURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            // The school folder has never been created. No courses, not a failure.
            return []
        }

        let folders = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return folders
            .map { folder in
                let notes = Self.markdownFiles(in: folder)
                let latest = notes.compactMap(Self.modified).max()
                return CourseFolder(
                    course: folder.lastPathComponent,
                    folder: "\(schoolFolder)/\(folder.lastPathComponent)",
                    noteCount: notes.count,
                    updated: latest.map(ISO8601Timestamp.string(from:))
                )
            }
            // Most recently written first, then by name so an empty course (and two written in the
            // same instant) still order predictably rather than by directory order.
            .sorted { left, right in
                switch (left.updated, right.updated) {
                case let (l?, r?) where l != r: return l > r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return left.course.localizedCaseInsensitiveCompare(right.course) == .orderedAscending
                }
            }
    }

    /// Minting deliberately does **not** require the knowledge root to already exist: it creates
    /// the whole chain, exactly as ``MarkdownKnowledgeService/capture(_:)`` does through its atomic
    /// write. A first note on a fresh install has to work, and "capture makes the root, taking a
    /// course note does not" would be an inconsistency the user would hit on day one.
    ///
    /// Reading is the asymmetric half, and stays that way: ``courses()`` reports a missing root as
    /// unavailable rather than as "no courses", the same distinction `note.list` draws.
    public func ensure(course: String) async throws -> CourseFolder {
        guard let name = CourseNaming.folderName(for: course) else {
            throw KnowledgeServiceError.writeFailed("“\(course)” is not a usable course name.")
        }
        let folderURL = schoolURL.appendingPathComponent(name)
        do {
            // Idempotent: an existing folder is left exactly as it is, notes and all.
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw KnowledgeServiceError.writeFailed(
                "The course folder could not be created: \(error.localizedDescription)"
            )
        }
        let notes = Self.markdownFiles(in: folderURL)
        return CourseFolder(
            course: name,
            folder: "\(schoolFolder)/\(name)",
            noteCount: notes.count,
            updated: notes.compactMap(Self.modified).max().map(ISO8601Timestamp.string(from:))
        )
    }

    public func createNote(course: String, title: String) async throws -> CourseNoteOutcome {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw KnowledgeServiceError.writeFailed("A note needs a title.")
        }
        // Taking a note is what brings a course into being, so the folder is minted here rather
        // than when a course is merely browsed — browsing must not leave empty folders behind.
        let folder = try await ensure(course: course)

        let now = clock.now()
        let day = Self.day(now)
        let filename = CourseNaming.noteFilename(date: day, title: trimmedTitle)
        let relativePath = "\(folder.folder)/\(filename)"
        let fileURL = schoolURL
            .appendingPathComponent(folder.course)
            .appendingPathComponent(filename)

        // Never overwrite. Two notes with the same title on the same day is a person opening the
        // one they already started, so the existing note is returned rather than replaced — the
        // same rule capture follows, with the friendlier outcome for a notebook.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return CourseNoteOutcome(
                course: folder.course, path: relativePath, title: trimmedTitle, created: false
            )
        }

        let content = Self.template(course: folder.course, title: trimmedTitle, now: now)
        do {
            try Data(content.utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw KnowledgeServiceError.writeFailed(
                "The note could not be written: \(error.localizedDescription)"
            )
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KnowledgeServiceError.writeFailed("The note was not present after writing.")
        }
        return CourseNoteOutcome(
            course: folder.course, path: relativePath, title: trimmedTitle, created: true
        )
    }

    // MARK: - The template

    /// The starting content of a course note (owner decision, 2026-08-04: "light structure").
    ///
    /// Enough scaffolding to start typing and generic enough for a lecture, a reading or a study
    /// session — deliberately **not** a study format like Cornell, which is excellent for lectures
    /// and wrong for everything else. Frontmatter carries the machine-readable facts so a future
    /// query can group by course without parsing headings, and the H1 repeats the title because a
    /// note should read correctly on its own, in any editor, with no frontmatter support at all.
    ///
    /// The keys are the ones the note port already understands (`title`, `updated`), so a course
    /// note lists, searches and reads exactly like every other note.
    static func template(course: String, title: String, now: Date) -> String {
        """
        ---
        title: \(title)
        course: \(course)
        created: \(ISO8601Timestamp.string(from: now))
        updated: \(ISO8601Timestamp.string(from: now))
        tags: [course-note]
        ---

        # \(title)

        \(day(now)) · \(course)

        ## Notes

        ## Questions

        ## Action items

        """
    }

    // MARK: - Helpers

    /// `YYYY-MM-DD` in the **local** calendar: a note taken at 11pm belongs to that evening's
    /// lecture, not to tomorrow, which a UTC date would claim for anyone west of Greenwich.
    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    /// The Markdown files directly inside a course folder. Not recursive: a course's notes are its
    /// own, and a nested folder is a sub-topic the user made, counted as part of neither.
    private static func markdownFiles(in folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries.filter { $0.pathExtension == "md" }
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
