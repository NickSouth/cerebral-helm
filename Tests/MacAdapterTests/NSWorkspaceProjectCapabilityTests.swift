// NIC-131 Increment 4: opening a repository directory in the configured editor.
//
// Exercised through a fake `WorkspaceOpening` so no real editor launches; the live
// NSWorkspace path is covered by manual smoke on hardware. Gated so Linux CI compiles
// this target empty.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralMacAdapters
import CerebralTools

/// Records the "open these documents with this app" calls the capability makes.
private final class RecordingWorkspace: WorkspaceOpening, @unchecked Sendable {
    let installed: [String: URL]
    private let lock = NSLock()
    private var opens: [(paths: [URL], app: URL)] = []

    init(installed: [String: URL]) { self.installed = installed }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? { installed[bundleID] }
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool { false }
    func openApplication(at url: URL) async throws {}
    func openApplication(at url: URL, arguments: [String]) async throws {}
    func openURL(_ url: URL) async throws {}

    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {
        record(paths: paths, app: applicationURL)
    }

    private func record(paths: [URL], app: URL) {
        lock.lock(); opens.append((paths, app)); lock.unlock()
    }

    var documentOpens: [(paths: [URL], app: URL)] {
        lock.lock(); defer { lock.unlock() }; return opens
    }
}

private let vscodeBundleID = "com.microsoft.VSCode"
private let vscodeURL = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")

private func projectsRootWithRepo(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("project-open-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true
    )
    return root.standardizedFileURL
}

private func editorReferences() -> [String: ReferenceEntry] {
    ["vscode": ReferenceEntry(id: "vscode", label: "Visual Studio Code", target: vscodeBundleID)]
}

@Test("opens a repo inside the projects root in the configured editor")
func opensRepoInEditor() async throws {
    let root = try projectsRootWithRepo(named: "demo")
    let repoPath = root.appendingPathComponent("demo").path
    let workspace = RecordingWorkspace(installed: [vscodeBundleID: vscodeURL])
    let capability = NSWorkspaceProjectCapability(
        appsProvider: { editorReferences() }, workspace: workspace, projectsRoot: root
    )

    let result = try await capability.open(repoPath: repoPath)

    #expect(result.opened)
    #expect(result.repoPath == repoPath)
    #expect(workspace.documentOpens.count == 1)
    #expect(workspace.documentOpens[0].app == vscodeURL)
    #expect(workspace.documentOpens[0].paths.first?.standardizedFileURL.path == repoPath)
}

@Test("a path outside the projects root is denied, and never reaches the editor")
func rejectsPathOutsideRoot() async throws {
    let root = try projectsRootWithRepo(named: "demo")
    let workspace = RecordingWorkspace(installed: [vscodeBundleID: vscodeURL])
    let capability = NSWorkspaceProjectCapability(
        appsProvider: { editorReferences() }, workspace: workspace, projectsRoot: root
    )

    await #expect(throws: NativeCapabilityError.permissionDenied) {
        _ = try await capability.open(repoPath: "/etc")
    }
    // A traversal attempt that escapes the root is denied too.
    await #expect(throws: NativeCapabilityError.permissionDenied) {
        _ = try await capability.open(repoPath: root.appendingPathComponent("../elsewhere").path)
    }
    #expect(workspace.documentOpens.isEmpty)
}

@Test("a repo path inside the root that doesn't exist is notFound")
func missingRepoIsNotFound() async throws {
    let root = try projectsRootWithRepo(named: "demo")
    let workspace = RecordingWorkspace(installed: [vscodeBundleID: vscodeURL])
    let capability = NSWorkspaceProjectCapability(
        appsProvider: { editorReferences() }, workspace: workspace, projectsRoot: root
    )
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.open(repoPath: root.appendingPathComponent("ghost").path)
    }
}

@Test("an unconfigured or uninstalled editor is notFound, not a silent success")
func missingEditorIsNotFound() async throws {
    let root = try projectsRootWithRepo(named: "demo")
    let repoPath = root.appendingPathComponent("demo").path

    // No editor reference configured.
    let unconfigured = NSWorkspaceProjectCapability(
        appsProvider: { [:] },
        workspace: RecordingWorkspace(installed: [vscodeBundleID: vscodeURL]),
        projectsRoot: root
    )
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await unconfigured.open(repoPath: repoPath)
    }

    // Editor configured but not installed (empty installed map).
    let uninstalled = NSWorkspaceProjectCapability(
        appsProvider: { editorReferences() },
        workspace: RecordingWorkspace(installed: [:]),
        projectsRoot: root
    )
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await uninstalled.open(repoPath: repoPath)
    }
}
#endif
