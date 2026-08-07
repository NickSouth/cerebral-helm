// Quick actions phase 5: handing one located note to Obsidian, or to Finder when nothing
// handles obsidian://.
//
// Exercised through a fake `WorkspaceOpening` and injected probe/reveal seams, so no real
// application launches. Gated so Linux CI compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralTools

/// Records the URLs handed to the workspace. Mutations run through non-async helpers so the lock
/// is never taken from an async context (Swift 6).
private final class RecordingNoteWorkspace: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    /// When set, `openURL` throws it — the "Launch Services refused" path.
    let failure: (any Error)?

    init(failure: (any Error)? = nil) { self.failure = failure }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? { nil }
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool { false }
    func openApplication(at url: URL) async throws {}
    func openApplication(at url: URL, arguments: [String]) async throws {}
    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {}

    func openURL(_ url: URL) async throws {
        record(url)
        if let failure { throw failure }
    }

    private func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var opened: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

/// Records what Finder was asked to reveal.
private final class RevealRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var revealed: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

private let notePath = "/Users/me/knowledge/inbox/Hull Plating.md"

@Test("with Obsidian present the note goes to obsidian://, and nothing is revealed in Finder")
func noteOpenPrefersObsidian() async throws {
    let workspace = RecordingNoteWorkspace()
    let reveals = RevealRecorder()
    let capability = ObsidianNoteOpenCapability(
        workspace: workspace,
        obsidianInstalled: { true },
        revealInFinder: { reveals.record($0) }
    )

    let result = try await capability.open(absolutePath: notePath)

    #expect(result == NoteOpenResult(opened: true, target: .obsidian))
    #expect(workspace.opened.count == 1)
    #expect(workspace.opened.first?.scheme == "obsidian")
    // The whole path rides as one escaped parameter value, spaces included.
    #expect(workspace.opened.first == ObsidianLink.openURL(forNote: notePath))
    // One destination, never both.
    #expect(reveals.revealed.isEmpty)
}

@Test("without an obsidian:// handler the note is revealed in Finder, and says so")
func noteOpenFallsBackToFinder() async throws {
    let workspace = RecordingNoteWorkspace()
    let reveals = RevealRecorder()
    let capability = ObsidianNoteOpenCapability(
        workspace: workspace,
        obsidianInstalled: { false },
        revealInFinder: { reveals.record($0) }
    )

    let result = try await capability.open(absolutePath: notePath)

    // `opened` stays true — the note really was surfaced — but the target is honest about which
    // surface took it, so the picker can say "revealed" rather than implying Obsidian opened.
    #expect(result == NoteOpenResult(opened: true, target: .finder))
    #expect(reveals.revealed == [URL(fileURLWithPath: notePath)])
    #expect(workspace.opened.isEmpty)
}

@Test("a refused open surfaces as a structured failure, never as an opened note")
func noteOpenReportsLaunchFailure() async {
    let capability = ObsidianNoteOpenCapability(
        workspace: RecordingNoteWorkspace(failure: NativeCapabilityError.permissionDenied),
        obsidianInstalled: { true },
        revealInFinder: { _ in }
    )

    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.open(absolutePath: notePath)
    }
}

@Test("an empty path is refused before anything is opened")
func noteOpenRefusesAnEmptyPath() async {
    let workspace = RecordingNoteWorkspace()
    let reveals = RevealRecorder()
    let capability = ObsidianNoteOpenCapability(
        workspace: workspace,
        obsidianInstalled: { true },
        revealInFinder: { reveals.record($0) }
    )

    // `URL(fileURLWithPath: "")` resolves to the working directory, so an empty path must fail
    // rather than quietly revealing somewhere real and entirely unrelated.
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.open(absolutePath: "   ")
    }
    #expect(workspace.opened.isEmpty)
    #expect(reveals.revealed.isEmpty)
}
#endif
