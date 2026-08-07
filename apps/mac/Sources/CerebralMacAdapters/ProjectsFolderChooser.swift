// Native folder picker for the `git-clone` form's location field (quick-actions phase 4).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Opens an `NSOpenPanel` rooted at the projects root and reports what the user chose.
///
/// **The root constraint is enforced here, not by the caller.** An open panel can navigate
/// anywhere, so `directoryURL` only decides where it *starts*; the selection is re-checked against
/// the projects root afterwards — after standardizing, so a symlinked path cannot slip past a
/// string comparison. A selection outside the root comes back as `outsideRoot`, which the form
/// explains, rather than as a path the tool would silently refuse later.
///
/// Cancelling and being refused are kept distinct on purpose: one deserves an explanation and the
/// other deserves silence.
public struct ProjectsFolderChooser: Sendable {
    private let projectsRoot: URL

    public init(projectsRoot: URL = WorkspacePaths.defaultProjectsRoot()) {
        self.projectsRoot = projectsRoot
    }

    /// Presents the panel and returns the selection. Always resolves — a cancelled panel is a
    /// normal outcome, not an error.
    @MainActor
    public func choose() async -> FolderSelectionInfo {
        // The root must exist for the panel to open there; a first-run machine with no projects
        // folder gets one rather than a panel that starts somewhere arbitrary.
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)

        // The dashboard lives in a backdrop window that never lifts, so the app has to be raised
        // or an app-modal panel can open behind whatever the user is actually looking at.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // New Folder is on, because "clone into a folder I am about to make" is a normal thing to
        // want and the alternative is making it in Finder first.
        panel.canCreateDirectories = true
        panel.directoryURL = projectsRoot
        panel.prompt = "Choose"
        panel.message = "Choose where to put the clone. It must be inside your projects folder."

        guard panel.runModal() == .OK, let chosen = panel.url else {
            return .cancelledSelection
        }
        return Self.classify(chosen, root: projectsRoot)
    }

    // MARK: - Pure helper (unit-tested)

    /// Classifies a chosen URL against the root: inside it (with the relative path, empty for the
    /// root itself), or refused.
    static func classify(_ chosen: URL, root: URL) -> FolderSelectionInfo {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = chosen.standardizedFileURL.resolvingSymlinksInPath().path

        if path == rootPath {
            return FolderSelectionInfo(absolutePath: path, relativePath: "", cancelled: false, outsideRoot: false)
        }
        guard path.hasPrefix(rootPath + "/") else {
            return FolderSelectionInfo(absolutePath: nil, relativePath: nil, cancelled: false, outsideRoot: true)
        }
        return FolderSelectionInfo(
            absolutePath: path,
            relativePath: String(path.dropFirst(rootPath.count + 1)),
            cancelled: false,
            outsideRoot: false
        )
    }
}
#endif
