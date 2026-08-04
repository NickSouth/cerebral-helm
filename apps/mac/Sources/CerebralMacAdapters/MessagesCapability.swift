// iMessage send + recipient listing (quick-actions phase 4) — the `send-text` action.
#if canImport(AppKit)
import Contacts
import Foundation
import CerebralCore
import CerebralTools

/// Sends one iMessage by exec'ing `osascript` with the message as an **argument**.
///
/// **The body is never part of the script text.** The script is a fixed `on run argv` document and
/// the recipient and body arrive as `argv` — verified — so a message containing quotes, `&`, or
/// the literal text `end tell` is data rather than syntax. Building the script by interpolation
/// would make every message the user types a potential AppleScript injection into their own
/// Messages app.
///
/// It composes over ``ProcessCapability`` for the same reason `git.clone` does: that adapter
/// already owns an exactly-specified environment, closed descriptors, a dedicated process group,
/// and timeouts. Nothing here re-earns those.
///
/// Sending needs the **Automation** permission for Messages, which macOS prompts for at first use.
/// A denial surfaces as `permissionDenied` rather than a silent no-op.
public struct MessagesCapability: MessagingCapability {
    private static let osascript = "/usr/bin/osascript"

    /// A fixed script. The only variables are `argv`, which is the whole point.
    ///
    /// `send … to` accepts a **participant or a chat** (verified against the scripting dictionary),
    /// which is why an existing group thread works. There is no creation command — the `chat` class
    /// is read-only — so a *new* group cannot be assembled here, and the form does not offer to.
    static let sendScript = """
    on run argv
      set targetKind to item 1 of argv
      set targetID to item 2 of argv
      set messageBody to item 3 of argv
      tell application "Messages"
        if targetKind is "chat" then
          send messageBody to chat id targetID
        else
          set targetService to 1st account whose service type = iMessage
          send messageBody to participant targetID of targetService
        end if
      end tell
      return "sent"
    end run
    """

    private let process: any ProcessCapability

    public init(process: any ProcessCapability = ProcessHookCapability()) {
        self.process = process
    }

    public func send(body: String, target: String, targetKind: String) async throws -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw NativeCapabilityError.adapterFailure("A message needs something to say.")
        }
        guard !target.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NativeCapabilityError.adapterFailure("A message needs a recipient.")
        }
        guard FileManager.default.fileExists(atPath: Self.osascript) else {
            throw NativeCapabilityError.notFound("osascript is not available on this machine.")
        }

        let result = try await process.run(HookInvocation(
            executable: Self.osascript,
            // The script is argument 1; everything after it is `argv`.
            arguments: ["-e", Self.sendScript, targetKind, target, trimmedBody],
            workingDirectory: NSTemporaryDirectory(),
            environment: ["PATH": "/usr/bin:/bin"]
        ))

        guard result.exitCode == 0 else {
            throw Self.sendFailure(from: result)
        }
        return true
    }

    /// Reads the reason out of `osascript`'s stderr. A refused Automation prompt is
    /// `permissionDenied` so the form can say what to grant, rather than "it failed".
    static func sendFailure(from result: ProcessRunResult) -> NativeCapabilityError {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // -1743 is the "not authorized to send Apple events" code; the text form appears too.
        if detail.contains("-1743") || detail.localizedCaseInsensitiveContains("not authorized") {
            return .permissionDenied
        }
        return .adapterFailure(
            detail.isEmpty ? "Messages refused the send (exit \(result.exitCode))." : detail
        )
    }
}

/// Lists who a message can go to: the user's contacts, and the existing chats Messages already has.
///
/// **A separate port from sending.** A surface that lists people must not be able to reach the one
/// that sends to them — the same split as calendars, Linear and the folder picker, and the place
/// it matters most.
///
/// Two grants, prompted at point of use: **Contacts** for the address book and **Automation** for
/// the chat list. Either can be refused independently, and a refusal drops that source rather than
/// failing the whole read — a contact list with no group threads is still usable.
public struct MessagesRecipientsProvider: MessageRecipientsProviding {
    private static let osascript = "/usr/bin/osascript"

    /// Lists existing chats with their participant counts. Named chats only: an unnamed one-to-one
    /// thread is already reachable through its contact, so listing it twice would just be noise.
    static let chatsScript = """
    on run argv
      set output to ""
      tell application "Messages"
        repeat with c in chats
          try
            set chatName to name of c
            if chatName is not missing value and chatName is not "" then
              set output to output & (id of c) & tab & chatName & tab & (count of participants of c) & linefeed
            end if
          end try
        end repeat
      end tell
      return output
    end run
    """

    private let process: any ProcessCapability

    public init(process: any ProcessCapability = ProcessHookCapability()) {
        self.process = process
    }

    public func recipients() async throws -> [MessageRecipient] {
        // Both sources are best-effort and independent: a refused Contacts grant should still
        // leave the group threads usable, and vice versa.
        async let contacts = (try? await self.contacts()) ?? []
        async let chats = (try? await self.chats()) ?? []
        return await chats + contacts
    }

    // MARK: - Contacts

    private func contacts() async throws -> [MessageRecipient] {
        // Created per read rather than stored: `CNContactStore` is not Sendable, and the read is
        // infrequent enough that a fresh store costs nothing.
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else {
            throw NativeCapabilityError.permissionDenied
        }
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var found: [MessageRecipient] = []
        try store.enumerateContacts(with: request) { contact, _ in
            found.append(contentsOf: Self.recipients(from: contact))
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One entry per reachable handle, not one per person: someone with a phone and an Apple ID is
    /// two ways to reach them, and the picker should let the user choose which.
    static func recipients(from contact: CNContact) -> [MessageRecipient] {
        let name = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return [] }

        let handles = contact.phoneNumbers.map(\.value.stringValue)
            + contact.emailAddresses.map { $0.value as String }
        return handles
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { MessageRecipient(id: $0, name: name, kind: "participant", groupSize: nil, handle: $0) }
    }

    // MARK: - Chats

    private func chats() async throws -> [MessageRecipient] {
        guard FileManager.default.fileExists(atPath: Self.osascript) else { return [] }
        let result = try await process.run(HookInvocation(
            executable: Self.osascript,
            arguments: ["-e", Self.chatsScript],
            workingDirectory: NSTemporaryDirectory(),
            environment: ["PATH": "/usr/bin:/bin"]
        ))
        guard result.exitCode == 0 else { throw NativeCapabilityError.permissionDenied }
        return Self.parseChats(result.stdout)
    }

    /// Parses the tab-separated chat listing. A malformed line is skipped rather than throwing —
    /// one odd thread must not cost the user the whole list.
    static func parseChats(_ output: String) -> [MessageRecipient] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { return nil }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !name.isEmpty else { return nil }
            let size = Int(parts[2].trimmingCharacters(in: .whitespaces))
            return MessageRecipient(
                id: id,
                name: name,
                kind: "chat",
                // Only a real group carries a size; a two-person thread is not a group.
                groupSize: (size ?? 0) > 1 ? size : nil,
                handle: nil
            )
        }
    }
}
#endif
