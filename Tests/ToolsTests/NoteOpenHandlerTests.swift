import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 5: the portable `note.open` handler resolves a root-relative path through
/// the knowledge service and hands the located file to the platform capability.
///
/// The split is the point of these tests. The **service** decides whether a path may resolve at
/// all; the **capability** only opens what it is given. So a path outside the root must fail
/// before the capability is ever reached — otherwise containment would depend on an adapter
/// remembering to re-check it.

private func library() -> MockKnowledgeService {
    MockKnowledgeService(entries: [
        NoteListEntry(
            path: "projects/atlas/kickoff.md", title: "Atlas kickoff", noteID: "ch-note-001",
            folder: "projects/atlas", project: "atlas", sensitivity: nil,
            updated: "2026-06-23T18:04:00Z"
        )
    ])
}

/// Records what it was asked to open, so the tests can assert the handler never joins a root to a
/// relative path itself — the capability must receive exactly what the service resolved.
private struct RecordingNoteOpen: NoteOpenCapability {
    let recorder: Recorder

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        // Mutated through a non-async helper: NSLock.lock() is unavailable from an async context.
        func record(_ path: String) {
            lock.lock()
            defer { lock.unlock() }
            value = path
        }
        var opened: String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func open(absolutePath: String) async throws -> NoteOpenResult {
        recorder.record(absolutePath)
        return NoteOpenResult(opened: true, target: .obsidian)
    }
}

@Test("note.open opens the located file and echoes the path the service resolved")
func noteOpenHandlerHappyPath() async throws {
    let recorder = RecordingNoteOpen.Recorder()
    let handler = NoteOpenHandler(
        knowledge: library(), capability: RecordingNoteOpen(recorder: recorder)
    )

    let output = try await handler.execute(
        input: Data(#"{"notePath":"projects/atlas/kickoff.md"}"#.utf8)
    )
    let decoded = try CerebralHelmNoteOpenOutput(data: output)

    #expect(decoded.noteOpened)
    #expect(decoded.noteOpenTarget == .obsidian)
    #expect(decoded.notePath == "projects/atlas/kickoff.md")
    // The absolute path came from the service, not from string-joining in the handler.
    #expect(recorder.opened == "\(MockKnowledgeService.root)/projects/atlas/kickoff.md")
}

@Test("note.open refuses a note the root does not contain, without reaching the capability")
func noteOpenHandlerRefusesUnknownNote() async throws {
    let recorder = RecordingNoteOpen.Recorder()
    let handler = NoteOpenHandler(
        knowledge: library(), capability: RecordingNoteOpen(recorder: recorder)
    )

    do {
        _ = try await handler.execute(input: Data(#"{"notePath":"elsewhere/secrets.md"}"#.utf8))
        Issue.record("a path the knowledge root does not contain must not open")
    } catch {
        // The failure is the point; which structured error it maps to is the service's contract.
    }
    // Nothing was handed to the platform: containment is decided before the adapter, always.
    #expect(recorder.opened == nil)
}

@Test("note.open rejects input that does not decode against its contract")
func noteOpenHandlerRejectsMalformedInput() async throws {
    let handler = NoteOpenHandler(
        knowledge: library(), capability: MockNoteOpenCapability(matrix: .allAvailable)
    )
    for bad in [#"{"notePath":123}"#, #"{}"#] {
        do {
            _ = try await handler.execute(input: Data(bad.utf8))
            Issue.record("\(bad) must be rejected as invalid input")
        } catch ToolHandlerError.invalidInput {
            continue
        }
    }
}

@Test("a path the schema's pattern excludes is still refused, by the service rather than the decoder")
func noteOpenHandlerRefusesNonMarkdown() async throws {
    let recorder = RecordingNoteOpen.Recorder()
    let handler = NoteOpenHandler(
        knowledge: library(), capability: RecordingNoteOpen(recorder: recorder)
    )

    // The generated decoder enforces TYPES, not JSON Schema patterns — so `.md` is not checked
    // there, and the knowledge service is what actually refuses. Worth pinning: the contract's
    // pattern is a first gate and documentation, never the boundary. The boundary holds anyway.
    for bad in ["inbox/notes.txt", "/absolute/inbox/note.md", "../escape.md"] {
        do {
            _ = try await handler.execute(input: Data(#"{"notePath":"\#(bad)"}"#.utf8))
            Issue.record("\(bad) must not open")
        } catch {
            continue
        }
    }
    #expect(recorder.opened == nil)
}

@Test("note.open with the platform capability unavailable is structured, never a fake success")
func noteOpenHandlerUnavailable() async throws {
    let handler = NoteOpenHandler(
        knowledge: library(), capability: MockNoteOpenCapability(matrix: .none)
    )
    do {
        _ = try await handler.execute(input: Data(#"{"notePath":"projects/atlas/kickoff.md"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable open must surface as unavailable, not as an opened note")
}
