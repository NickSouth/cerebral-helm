// Note opening (quick actions phase 5) — the `search-notes` picker's actuator.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Hands one note to Obsidian, or reveals it in Finder when nothing handles `obsidian://`.
///
/// **It never decides which note.** The absolute path arrives from
/// `KnowledgeService.locate(_:)`, which has already proved it resolves inside the knowledge root;
/// this adapter's whole job is the hand-off. There is deliberately no root here to join a relative
/// path against — that arithmetic is where a containment rule gets accidentally re-implemented, and
/// a second rule could only disagree with the first.
///
/// The Finder fallback is the same policy the Setup panel's "Browse in Obsidian" uses (NIC-162):
/// without Obsidian the note is still revealed, so the action does something real, and the caller
/// is told which surface took it rather than being left to assume.
///
/// **A known limitation, reported honestly rather than hidden:** Obsidian can only open a file
/// inside a vault it has already registered, and its URI scheme has no "add this vault" command.
/// Nothing here can detect that state — the URL is accepted either way — so a first run needs the
/// user to add the knowledge folder in Obsidian once. The picker carries that hint.
public struct ObsidianNoteOpenCapability: NoteOpenCapability {
    private let workspace: any WorkspaceOpening
    private let obsidianInstalled: @Sendable () -> Bool
    private let revealInFinder: @Sendable (URL) -> Void

    public init(
        workspace: any WorkspaceOpening = SystemWorkspace(),
        obsidianInstalled: @escaping @Sendable () -> Bool = { Self.systemHandlesObsidianScheme() },
        revealInFinder: @escaping @Sendable (URL) -> Void = { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    ) {
        self.workspace = workspace
        self.obsidianInstalled = obsidianInstalled
        self.revealInFinder = revealInFinder
    }

    public func open(absolutePath: String) async throws -> NoteOpenResult {
        let trimmed = absolutePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeCapabilityError.adapterFailure("There is no note to open.")
        }

        switch ObsidianLink.destination(forNote: trimmed, obsidianInstalled: obsidianInstalled()) {
        case let .obsidian(url):
            do {
                try await workspace.openURL(url)
            } catch is CancellationError {
                throw NativeCapabilityError.cancelled
            } catch let error as NativeCapabilityError {
                throw error
            } catch {
                throw NativeCapabilityError.adapterFailure(
                    "Obsidian could not open the note: \(error.localizedDescription)"
                )
            }
            return NoteOpenResult(opened: true, target: .obsidian)
        case let .revealInFinder(url):
            // Synchronous and unfailing in AppKit: there is no completion to await and no error
            // to surface, so this reports what it did rather than inventing a success signal.
            revealInFinder(url)
            return NoteOpenResult(opened: true, target: .finder)
        }
    }

    /// Whether anything on this Mac handles `obsidian://`. Probed per call rather than cached,
    /// matching `WindowCoordinator.obsidianInstalled`: the user may install Obsidian while the
    /// app is running, and a cached "no" would outlive the fact.
    public static func systemHandlesObsidianScheme() -> Bool {
        guard let probe = URL(string: "obsidian://open") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }
}
#endif
