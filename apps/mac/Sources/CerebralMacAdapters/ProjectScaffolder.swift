// Project scaffolding (quick-actions phase 4) — the `create-project` action's actuator.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Creates a project folder under the projects root and writes its `PROJECT.md`.
///
/// **A project folder is a container, not a repository.** `FileSystemActiveProjectsProvider` reads
/// projects at depth 1 and `FileSystemActiveReposProvider` finds the git repos one level *inside*
/// them, so this deliberately runs no `git init`: a project folder that was itself a repo would be
/// a different shape from every project the widget already reads. Cloning into it afterwards is
/// what `git-clone`'s location picker is for.
///
/// Containment matches ``MacGitCloneCapability`` exactly — resolved inside the root, re-checked
/// after standardizing so `..` cannot escape, and an existing path is a refusal rather than an
/// overwrite. Unlike the clone this runs no process at all: it is two filesystem writes.
public struct ProjectScaffolder: ProjectScaffoldCapability {
    private let projectsRoot: URL

    public init(projectsRoot: URL = WorkspacePaths.defaultProjectsRoot()) {
        self.projectsRoot = projectsRoot
    }

    public func scaffold(
        name: String, location: String?, summary: String?, importance: Int?
    ) async throws -> ProjectScaffoldResult {
        let folder = try Self.folderName(from: name)
        let target = try Self.resolveTarget(root: projectsRoot, location: location, folder: folder)

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: target.path) else {
            throw NativeCapabilityError.adapterFailure(
                "'\(folder)' already exists in your projects folder. Choose a different name."
            )
        }
        do {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw NativeCapabilityError.adapterFailure(
                "Could not create '\(target.path)': \(error.localizedDescription)"
            )
        }

        let descriptor = target.appendingPathComponent(
            FileSystemActiveProjectsProvider.descriptorFilename, isDirectory: false
        )
        do {
            try Self.descriptorContents(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: summary,
                importance: importance
            ).write(to: descriptor, atomically: true, encoding: .utf8)
        } catch {
            // A folder with no descriptor still lists in the widget, but it is not what was asked
            // for — so the half-made project goes rather than being reported as a success.
            try? fileManager.removeItem(at: target)
            throw NativeCapabilityError.adapterFailure(
                "Could not write the project descriptor: \(error.localizedDescription)"
            )
        }
        return ProjectScaffoldResult(projectPath: target.path, descriptorPath: descriptor.path)
    }

    // MARK: - Pure helpers (unit-tested)

    /// The default `importance` the shipped template carries, used when the form leaves it blank.
    static let defaultImportance = 5

    /// The folder name for a project name. A separator is **refused, not sanitized**: silently
    /// turning "Helm / v2" into a nested folder would put the project somewhere the user did not
    /// ask for, and a name they can see is wrong is better than a path they cannot.
    static func folderName(from name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeCapabilityError.adapterFailure("A project needs a name.")
        }
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            throw NativeCapabilityError.adapterFailure(
                "A project name can't contain '/' or ':'. Use the location field to nest it."
            )
        }
        // A leading dot would create something the Finder and the projects reader both hide.
        guard !trimmed.hasPrefix(".") else {
            throw NativeCapabilityError.adapterFailure("A project name can't start with a dot.")
        }
        return trimmed
    }

    /// Resolves `<root>/<location>/<folder>` and re-checks containment after standardizing, so a
    /// `..` in either part cannot escape. The root itself is never the destination.
    static func resolveTarget(root: URL, location: String?, folder: String) throws -> URL {
        let rootPath = root.standardizedFileURL.path
        var target = root
        if let location {
            let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
                    throw NativeCapabilityError.permissionDenied
                }
                target = target.appendingPathComponent(trimmed)
            }
        }
        target = target.appendingPathComponent(folder).standardizedFileURL
        guard target.path.hasPrefix(rootPath + "/"), target.path != rootPath else {
            throw NativeCapabilityError.permissionDenied
        }
        return target
    }

    /// The `PROJECT.md` body.
    ///
    /// Composed here rather than by substituting into `config/templates/PROJECT.md`: that template
    /// is a hand-authoring reference with prose placeholders, and string-replacing into prose is
    /// the kind of thing that works until someone edits a sentence. The shape is held to the
    /// template's by a test, which is a check that survives edits to either.
    static func descriptorContents(name: String, summary: String?, importance: Int?) -> String {
        let weight = importance ?? defaultImportance
        let line = (summary?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "One-line summary of what this project is."
        return """
        ---
        importance: \(weight)
        ---

        # \(name)

        _\(line)_

        ## Focus

        - First priority

        ## Notes

        Add any context worth surfacing in the dashboard.

        """
    }
}
#endif
