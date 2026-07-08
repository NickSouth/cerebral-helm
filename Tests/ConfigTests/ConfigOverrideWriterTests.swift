import Foundation
import Testing
import CerebralContracts
import CerebralCore

/// FR-CFG-04: the programmatic config-write path validates through the same
/// layered load as manual edits, writes atomically, and rolls back a rejected
/// candidate so the disk and the active config never diverge.

private func writerRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func makeWorkspace() throws -> WorkspacePaths {
    try WorkspacePaths.temporary(repositoryRoot: writerRepositoryRoot())
}

private func override(
    _ modeID: String, quickApps: [String]?
) -> CerebralHelmModeOverride {
    CerebralHelmModeOverride(extensions: nil, id: modeID, quickApps: quickApps, schemaVersion: "1.0.0")
}

private func overrideFile(_ paths: WorkspacePaths, _ modeID: String) -> URL {
    paths.overridesDirectory.appendingPathComponent("\(modeID).json")
}

@Test("a valid write activates and the loader reads it back (FR-CFG-04)")
func validWriteActivates() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)

    guard case let .applied(active) = writer.write(override("developer", quickApps: ["vscode", "terminal"])) else {
        Issue.record("expected the write to apply")
        return
    }
    #expect(active.mode(id: "developer")?.quickApps == ["vscode", "terminal"])

    // A manual-edit-equivalent read — a fresh loader over the same workspace —
    // sees the identical merged configuration.
    guard case let .activated(reloaded) = ConfigLoader(workspace: paths).load() else {
        Issue.record("expected the written override to activate on reload")
        return
    }
    #expect(reloaded.mode(id: "developer")?.quickApps == ["vscode", "terminal"])
}

@Test("a second write replaces the first (one canonical file per mode)")
func secondWriteReplacesFirst() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)

    _ = writer.write(override("developer", quickApps: ["vscode"]))
    guard case let .applied(active) = writer.write(override("developer", quickApps: ["terminal", "xcode"])) else {
        Issue.record("expected the replacing write to apply")
        return
    }
    #expect(active.mode(id: "developer")?.quickApps == ["terminal", "xcode"])
}

@Test("an invalid document is rejected before anything touches disk")
func invalidDocumentRejectedWithoutWriting() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)

    // Six quick apps exceed the schema's five slots.
    let outcome = writer.write(override("developer", quickApps: ["a", "b", "c", "d", "e", "f"]))
    guard case let .rejected(errors) = outcome else {
        Issue.record("expected the oversized override to be rejected")
        return
    }
    #expect(!errors.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: overrideFile(paths, "developer").path))
}

@Test("an override for an unconfigured mode is rejected and rolled back")
func unknownModeRejectedAndRolledBack() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)

    let outcome = writer.write(override("retired-mode", quickApps: ["vscode"]))
    guard case let .rejected(errors) = outcome else {
        Issue.record("expected the unknown-mode override to be rejected")
        return
    }
    #expect(errors.contains { $0.field == "/id" })
    // The candidate file did not survive rejection.
    #expect(!FileManager.default.fileExists(atPath: overrideFile(paths, "retired-mode").path))
}

@Test("a rejected replacement restores the previous valid override (rollback)")
func rejectedReplacementRestoresPrevious() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)
    _ = writer.write(override("developer", quickApps: ["vscode"]))

    // Corrupt the workspace with a second, invalid override file so the layered
    // load rejects any candidate; the writer must restore what it replaced.
    try FileManager.default.createDirectory(at: paths.overridesDirectory, withIntermediateDirectories: true)
    let broken = paths.overridesDirectory.appendingPathComponent("aa-broken.json")
    try Data(#"{"schemaVersion":"1.0.0","id":"developer","riskOverride":"read_only"}"#.utf8).write(to: broken)

    guard case .rejected = writer.write(override("developer", quickApps: ["terminal"])) else {
        Issue.record("expected the write to be rejected while the workspace is invalid")
        return
    }
    let restored = try CerebralHelmModeOverride(data: Data(contentsOf: overrideFile(paths, "developer")))
    #expect(restored.quickApps == ["vscode"])
}

@Test("remove reverts the mode to its shipped default and is idempotent")
func removeRevertsToShippedDefault() throws {
    let paths = try makeWorkspace()
    let writer = ConfigOverrideWriter(workspace: paths)
    _ = writer.write(override("developer", quickApps: ["vscode"]))

    guard case let .applied(active) = writer.remove(modeID: "developer") else {
        Issue.record("expected the removal to apply")
        return
    }
    // Back to the shipped developer.json quick apps — clean slate since the
    // release-MVP decision (users pin their own; modes ship none).
    #expect(active.mode(id: "developer")?.quickApps == [])
    #expect(!FileManager.default.fileExists(atPath: overrideFile(paths, "developer").path))

    // Removing an already-absent override still reports the active config.
    guard case .applied = writer.remove(modeID: "developer") else {
        Issue.record("expected the idempotent removal to apply")
        return
    }
}
