// Quick actions phase 4: sending an iMessage, and listing who it could go to.
//
// Nothing here sends a real message. The script's *shape* is what carries the safety property, so
// that is what is asserted; an end-to-end send needs an Automation grant and is a manual step.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore
import CerebralTools

/// Records the invocation instead of running it. Mutations go through a non-async helper so the
/// lock is never taken from an async context (Swift 6).
private final class RecordingProcess: ProcessCapability, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HookInvocation] = []
    let exitCode: Int
    let stdout: String
    let stderr: String

    init(exitCode: Int = 0, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        record(invocation)
        return ProcessRunResult(
            exitCode: exitCode, stdout: stdout, stderr: stderr,
            environment: invocation.environment, timedOut: false, durationMs: 3
        )
    }

    private func record(_ invocation: HookInvocation) { lock.lock(); seen.append(invocation); lock.unlock() }

    var invocations: [HookInvocation] { lock.lock(); defer { lock.unlock() }; return seen }
}

@Test("the message is an ARGUMENT, never part of the script text")
func messagesSendIsInjectionSafe() async throws {
    // The safety property of this whole adapter. A body containing quotes, an ampersand and the
    // literal `end tell` must travel as data — building the script by interpolation would make
    // every message the user types an AppleScript injection into their own Messages app.
    let process = RecordingProcess()
    let capability = MessagesCapability(process: process)
    let nasty = #"he said "hi" & then } end tell tell application "Finder" to delete"#

    _ = try await capability.send(body: nasty, target: "+15551234567", targetKind: "participant")

    let invocation = try #require(process.invocations.first)
    #expect(invocation.executable == "/usr/bin/osascript")
    // The script is argument 2 (after `-e`); the recipient and body follow it as argv.
    #expect(invocation.arguments[0] == "-e")
    #expect(invocation.arguments[1] == MessagesCapability.sendScript)
    #expect(invocation.arguments.last == nasty)
    // The script itself never contains the body.
    #expect(!MessagesCapability.sendScript.contains("hi"))
    #expect(!invocation.arguments[1].contains(nasty))
}

@Test("the script routes a chat and a participant differently, and can create neither")
func messagesSendScriptShape() {
    let script = MessagesCapability.sendScript
    // `send … to` accepts a participant or a chat — verified against the scripting dictionary.
    #expect(script.contains("send messageBody to chat id targetID"))
    #expect(script.contains("send messageBody to participant targetID of targetService"))
    // There is no creation command in the dictionary, and none here: a NEW group cannot be
    // assembled, so nothing pretends it can.
    #expect(!script.contains("make new"))
}

@Test("an empty body or recipient is refused before anything is exec'd")
func messagesSendRefusesEmpty() async {
    let process = RecordingProcess()
    let capability = MessagesCapability(process: process)
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.send(body: "   ", target: "+1555", targetKind: "participant")
    }
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await capability.send(body: "Hi", target: " ", targetKind: "participant")
    }
    #expect(process.invocations.isEmpty)
}

@Test("a refused Automation prompt reads as permissionDenied, not a generic failure")
func messagesSendMapsPermissionDenial() {
    // The user can fix this in one step, so it must not arrive as "it failed".
    let denied = ProcessRunResult(
        exitCode: 1, stdout: "",
        stderr: "execution error: Not authorized to send Apple events to Messages. (-1743)",
        environment: [:], timedOut: false, durationMs: 1
    )
    #expect(MessagesCapability.sendFailure(from: denied) == .permissionDenied)

    let other = ProcessRunResult(
        exitCode: 1, stdout: "", stderr: "execution error: something else",
        environment: [:], timedOut: false, durationMs: 1
    )
    if case .permissionDenied = MessagesCapability.sendFailure(from: other) {
        Issue.record("an unrelated failure must not be reported as a permission problem")
    }
}

@Test("chats parse with their group size, and a malformed line is skipped")
func messagesParsesChats() {
    let output = """
    chat1\tSki trip\t6
    chat2\tPair\t2
    broken-line
    \tNo id\t3
    """
    let parsed = MessagesRecipientsProvider.parseChats(output)
    #expect(parsed.map(\.name) == ["Ski trip", "Pair"])
    #expect(parsed[0].groupSize == 6)
    #expect(parsed[0].kind == "chat")
    // A named two-person thread still reports its size: the disclosure states what it found
    // rather than deciding on the user's behalf where "group" starts.
    #expect(parsed[1].groupSize == 2)
}

@Test("the chat listing never tries to create anything")
func messagesChatsScriptIsReadOnly() {
    #expect(!MessagesRecipientsProvider.chatsScript.contains("make new"))
    #expect(MessagesRecipientsProvider.chatsScript.contains("count of participants"))
}
#endif
