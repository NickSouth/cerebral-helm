// Quick actions phase 4, action 2: cloning a repository into the projects root.
//
// The safety invariants are pure functions and are tested directly; the end-to-end clone runs a
// real `git` against a real network and is covered by manual smoke on hardware. Gated so Linux CI
// compiles this target empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore
import CerebralTools

private let root = URL(fileURLWithPath: "/Users/example/Projects", isDirectory: true)

// MARK: - Source URL

@Test("only https repository URLs are accepted")
func gitCloneAcceptsOnlyHTTPS() throws {
    #expect(try MacGitCloneCapability.validatedSource("https://github.com/o/r.git").host == "github.com")

    // ssh and the scp-like form reach for credentials this tool has no business using; file://
    // would turn "clone" into a local copy tool with a caller-chosen source path.
    for refused in ["ssh://git@github.com/o/r.git", "file:///etc", "git://github.com/o/r.git"] {
        #expect(throws: NativeCapabilityError.self) {
            _ = try MacGitCloneCapability.validatedSource(refused)
        }
    }
}

@Test("a URL carrying embedded credentials is refused, not redacted")
func gitCloneRefusesEmbeddedCredentials() {
    // Refusing keeps the token out of the command log entirely; redacting means it already
    // arrived and we merely hid it afterwards.
    #expect(throws: NativeCapabilityError.self) {
        _ = try MacGitCloneCapability.validatedSource("https://someone:ghp_secret@github.com/o/r.git")
    }
}

@Test("text that is not a URL at all is refused")
func gitCloneRefusesNonURL() {
    #expect(throws: NativeCapabilityError.self) {
        _ = try MacGitCloneCapability.validatedSource("not a url")
    }
}

// MARK: - Folder name

@Test("the folder name is derived from the repository, with .git stripped")
func gitCloneDerivesFolderName() throws {
    let url = try MacGitCloneCapability.validatedSource("https://github.com/NickSouth/cerebral-helm.git")
    #expect(try MacGitCloneCapability.folderName(directory: nil, repositoryURL: url) == "cerebral-helm")
    #expect(try MacGitCloneCapability.folderName(directory: "  ", repositoryURL: url) == "cerebral-helm")
    // A supplied name wins, including a nested one.
    #expect(try MacGitCloneCapability.folderName(directory: "CerebralHelm/helm", repositoryURL: url) == "CerebralHelm/helm")
}

@Test("an absolute or home-relative folder is refused outright")
func gitCloneRefusesAbsoluteFolder() throws {
    let url = try MacGitCloneCapability.validatedSource("https://github.com/o/r.git")
    for refused in ["/tmp/elsewhere", "~/Desktop"] {
        #expect(throws: NativeCapabilityError.self) {
            _ = try MacGitCloneCapability.folderName(directory: refused, repositoryURL: url)
        }
    }
}

// MARK: - Containment

@Test("the destination is resolved inside the projects root")
func gitCloneResolvesInsideRoot() throws {
    let target = try MacGitCloneCapability.resolveTarget(root: root, folder: "cerebral-helm")
    #expect(target.path == "/Users/example/Projects/cerebral-helm")

    let nested = try MacGitCloneCapability.resolveTarget(root: root, folder: "CerebralHelm/helm")
    #expect(nested.path == "/Users/example/Projects/CerebralHelm/helm")
}

@Test("a relative escape cannot place a clone outside the projects root")
func gitCloneRefusesEscape() {
    // The invariant that makes this tool narrow: containment is re-checked AFTER standardizing,
    // so `..` is resolved away before the comparison rather than matched as a string.
    for escape in ["../Desktop", "a/../../Desktop", "..", "."] {
        #expect(throws: NativeCapabilityError.self) {
            _ = try MacGitCloneCapability.resolveTarget(root: root, folder: escape)
        }
    }
}

// MARK: - Failure reporting

@Test("a failed clone reports git's own reason, not just an exit code")
func gitCloneReportsStderr() {
    let failed = ProcessRunResult(
        exitCode: 128,
        stdout: "",
        stderr: "fatal: repository 'https://github.com/o/r.git' not found\n",
        environment: [:],
        timedOut: false,
        durationMs: 12
    )
    #expect(MacGitCloneCapability.failureMessage(from: failed).contains("not found"))

    let silent = ProcessRunResult(
        exitCode: 1, stdout: "", stderr: "   ", environment: [:], timedOut: false, durationMs: 1
    )
    #expect(MacGitCloneCapability.failureMessage(from: silent).contains("exit code 1"))
}

// MARK: - Folder picker classification

@Test("a picked folder inside the root comes back relative to it")
func folderPickerClassifiesInsideRoot() {
    let inside = ProjectsFolderChooser.classify(
        URL(fileURLWithPath: "/Users/example/Projects/CerebralHelm"), root: root
    )
    #expect(inside.relativePath == "CerebralHelm")
    #expect(inside.outsideRoot == false)
    #expect(inside.cancelled == false)

    // The root itself is a valid choice — it means "top of the projects folder".
    let atRoot = ProjectsFolderChooser.classify(root, root: root)
    #expect(atRoot.relativePath == "")
    #expect(atRoot.outsideRoot == false)
}

@Test("a picked folder outside the root is refused, and refusal is not cancellation")
func folderPickerRefusesOutsideRoot() {
    // An open panel can navigate anywhere, so `directoryURL` only decides where it STARTS. The
    // constraint has to be re-checked on the way back.
    let outside = ProjectsFolderChooser.classify(URL(fileURLWithPath: "/Users/example/Desktop"), root: root)
    #expect(outside.outsideRoot)
    #expect(outside.cancelled == false, "refused and cancelled are different facts")
    #expect(outside.relativePath == nil)

    // A sibling whose path merely starts with the root's characters is still outside it.
    let sibling = ProjectsFolderChooser.classify(URL(fileURLWithPath: "/Users/example/ProjectsOld"), root: root)
    #expect(sibling.outsideRoot)
}

// MARK: - End to end, with a fake process

/// Records the invocation instead of running it, so the clone path is exercised without a network.
private final class RecordingProcess: ProcessCapability, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HookInvocation] = []
    let exitCode: Int
    let stderr: String

    init(exitCode: Int = 0, stderr: String = "") {
        self.exitCode = exitCode
        self.stderr = stderr
    }

    func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        // Recorded through a non-async helper so the lock is never taken from an async context
        // (Swift 6) — the same shape the other adapter recorders use.
        record(invocation)
        return ProcessRunResult(
            exitCode: exitCode, stdout: "", stderr: stderr, environment: invocation.environment,
            timedOut: false, durationMs: 5
        )
    }

    private func record(_ invocation: HookInvocation) { lock.lock(); seen.append(invocation); lock.unlock() }

    var invocations: [HookInvocation] { lock.lock(); defer { lock.unlock() }; return seen }
}

@Test("the clone execs a fixed git with a typed argument list and no interactive prompt")
func gitCloneExecsFixedGit() async throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ch-clone-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let process = RecordingProcess()
    let capability = MacGitCloneCapability(process: process, projectsRoot: temporaryRoot)

    let result = try await capability.clone(
        repositoryURL: "https://github.com/NickSouth/cerebral-helm.git", directory: nil
    )

    #expect(result.repositoryName == "cerebral-helm")
    #expect(result.clonedPath.hasSuffix("/cerebral-helm"))

    let invocation = try #require(process.invocations.first)
    #expect(invocation.executable == "/usr/bin/git")
    #expect(invocation.arguments.first == "clone")
    #expect(invocation.arguments.count == 3)
    // No credential prompt can block a clone forever behind a window nobody can see.
    #expect(invocation.environment["GIT_TERMINAL_PROMPT"] == "0")
}

@Test("an existing folder is a refusal, never an overwrite")
func gitCloneRefusesExistingFolder() async throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ch-clone-\(UUID().uuidString)", isDirectory: true)
    let occupied = temporaryRoot.appendingPathComponent("cerebral-helm", isDirectory: true)
    try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let process = RecordingProcess()
    let capability = MacGitCloneCapability(process: process, projectsRoot: temporaryRoot)

    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.clone(
            repositoryURL: "https://github.com/NickSouth/cerebral-helm.git", directory: nil
        )
    }
    // It refused before running anything at all.
    #expect(process.invocations.isEmpty)
}
#endif
