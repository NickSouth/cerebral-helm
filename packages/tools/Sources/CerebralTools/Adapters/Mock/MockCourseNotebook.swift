import Foundation
import CerebralCore

/// Deterministic mock course notebook for the pre-Mac foundation and the contract suite.
///
/// Holds courses in memory and applies the **same rules** the durable one does — the folder name
/// is derived through ``CourseNaming`` rather than taken from the caller, and a note is never
/// overwritten — so a test that passes here is exercising the real contract rather than a
/// permissive stand-in.
public final class MockCourseNotebook: CourseNotebook, @unchecked Sendable {
    public let schoolFolder: String
    /// The stand-in day for a created note's filename, so the mock's paths are stable.
    public let day: String

    private let lock = NSLock()
    private var folders: [String: [String]] = [:]
    /// When true, every call reports the knowledge root as unreachable — the canonical failure.
    public var rootAvailable: Bool

    public init(
        schoolFolder: String = "areas/school-umass",
        courses: [String: [String]] = [:],
        day: String = "2026-08-04",
        rootAvailable: Bool = true
    ) {
        self.schoolFolder = schoolFolder
        self.folders = courses
        self.day = day
        self.rootAvailable = rootAvailable
    }

    public func courses() async throws -> [CourseFolder] {
        try requireRoot()
        return snapshot()
            .map { name, notes in
                CourseFolder(
                    course: name,
                    folder: "\(schoolFolder)/\(name)",
                    noteCount: notes.count,
                    updated: notes.isEmpty ? nil : "2026-08-04T12:00:00Z"
                )
            }
            .sorted { $0.course < $1.course }
    }

    public func ensure(course: String) async throws -> CourseFolder {
        try requireRoot()
        guard let name = CourseNaming.folderName(for: course) else {
            throw KnowledgeServiceError.writeFailed("“\(course)” is not a usable course name.")
        }
        add(name)
        return CourseFolder(
            course: name,
            folder: "\(schoolFolder)/\(name)",
            noteCount: notes(in: name).count,
            updated: nil
        )
    }

    public func createNote(course: String, title: String) async throws -> CourseNoteOutcome {
        try requireRoot()
        let folder = try await ensure(course: course)
        let filename = CourseNaming.noteFilename(date: day, title: title)
        let path = "\(folder.folder)/\(filename)"
        // Never overwrite: an existing note of that title on that day is returned as-is.
        if notes(in: folder.course).contains(filename) {
            return CourseNoteOutcome(course: folder.course, path: path, title: title, created: false)
        }
        append(filename, to: folder.course)
        return CourseNoteOutcome(course: folder.course, path: path, title: title, created: true)
    }

    // Mutations run through non-async helpers so the lock is never taken from an async context.
    private func requireRoot() throws {
        guard rootAvailable else { throw KnowledgeServiceError.rootUnavailable }
    }
    private func snapshot() -> [String: [String]] {
        lock.lock(); defer { lock.unlock() }; return folders
    }
    private func notes(in course: String) -> [String] {
        lock.lock(); defer { lock.unlock() }; return folders[course] ?? []
    }
    private func add(_ course: String) {
        lock.lock(); defer { lock.unlock() }
        if folders[course] == nil { folders[course] = [] }
    }
    private func append(_ filename: String, to course: String) {
        lock.lock(); defer { lock.unlock() }
        folders[course, default: []].append(filename)
    }
}
