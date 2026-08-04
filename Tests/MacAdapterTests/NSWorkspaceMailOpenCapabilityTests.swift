// Gmail links: the URL they resolve to, and the Chrome profile they open in.
//
// This capability shipped written-but-unwired — `MacToolCapabilities` never passed it, so the
// default mock (matrix `.none`) silently took its place and every report link did nothing. These
// tests cover the behavior; the wiring itself is covered by `macCapabilitiesDeclareMailOpen`.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters
import CerebralTools

private func mailWorkspace(hasChrome: Bool = true) -> LauncherWorkspace {
    LauncherWorkspace(hasChrome: hasChrome)
}

// MARK: - URL building

@Test("a message id becomes an rfc822msgid search, addressed to the connected account")
func mailURLAddressesTheAccount() throws {
    let url = try #require(NSWorkspaceMailOpenCapability.mailURL(
        messageID: "CA+abc123@mail.example.com", address: "nick@gmail.com"
    ))
    #expect(url.absoluteString == "https://mail.google.com/mail/u/nick@gmail.com/#search/rfc822msgid:CA%2Babc123%40mail.example.com")
}

@Test("no message id opens that account's inbox")
func mailURLInboxForAccount() throws {
    let url = try #require(NSWorkspaceMailOpenCapability.mailURL(messageID: nil, address: "nick@gmail.com"))
    #expect(url.absoluteString == "https://mail.google.com/mail/u/nick@gmail.com/#inbox")
}

@Test("without a recorded address it falls back to the default account")
func mailURLFallsBackToDefaultAccount() throws {
    // `u/0` is "whichever account signed in first", which is why it is the fallback and not the
    // rule — a grant stored before addresses existed still works, just less precisely.
    let inbox = try #require(NSWorkspaceMailOpenCapability.mailURL(messageID: nil, address: nil))
    #expect(inbox.absoluteString == "https://mail.google.com/mail/u/0/#inbox")

    let blank = try #require(NSWorkspaceMailOpenCapability.mailURL(messageID: "x@y", address: "   "))
    #expect(blank.absoluteString.hasPrefix("https://mail.google.com/mail/u/0/#search/"))
}

@Test("angle brackets are stripped and the id cannot escape its fragment")
func mailURLEncodesTheMessageID() throws {
    let url = try #require(NSWorkspaceMailOpenCapability.mailURL(
        messageID: "  <id#with/slash?q=1@host>  ", address: nil
    ))
    // A second `#`, a `/`, or a `?` would change what the browser opens — all percent-encoded.
    #expect(url.absoluteString == "https://mail.google.com/mail/u/0/#search/rfc822msgid:id%23with%2Fslash%3Fq%3D1%40host")
}

@Test("a blank message id opens the inbox rather than an empty search")
func mailURLBlankMessageIDOpensInbox() throws {
    let url = try #require(NSWorkspaceMailOpenCapability.mailURL(messageID: "   ", address: nil))
    #expect(url.absoluteString == NSWorkspaceMailOpenCapability.inboxURL)
}

// MARK: - Profile routing

@Test("mail opens in the Chrome profile signed into the connected account")
func mailOpensInTheAccountsProfile() async throws {
    let workspace = mailWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting, settle: {}
    )
    let capability = NSWorkspaceMailOpenCapability(
        workspace: workspace,
        accountAddress: { "nsouthey@umass.edu" },
        // Chrome's own Local State says the school account lives in "Profile 1".
        profileForAccount: { $0 == "nsouthey@umass.edu" ? "Profile 1" : nil },
        chromeLauncher: launcher,
        currentModeProvider: { "school" }
    )

    let result = try await capability.open(messageID: "abc@host")

    #expect(result.opened)
    // Launched into that profile, carrying the account-addressed URL.
    let launch = try #require(workspace.recordedLaunches.first)
    #expect(launch.contains("--profile-directory=Profile 1"))
    #expect(launch.contains("https://mail.google.com/mail/u/nsouthey@umass.edu/#search/rfc822msgid:abc%40host"))
}

@Test("a second link reuses the profile's window instead of opening another")
func mailReusesTheProfileWindow() async throws {
    let workspace = mailWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(workspace: workspace, scripting: scripting, settle: {})
    let capability = NSWorkspaceMailOpenCapability(
        workspace: workspace,
        accountAddress: { "nick@gmail.com" },
        profileForAccount: { _ in "Default" },
        chromeLauncher: launcher,
        currentModeProvider: { "executive" }
    )

    // First open launches and the launcher records the window that appeared.
    scripting.setWindows([], front: nil)
    _ = try await capability.open(messageID: nil)
    scripting.setWindows([7], front: 7)
    _ = try await capability.open(messageID: nil)
    // Window 7 now holds a Gmail tab — the second link should surface it, not stack another.
    scripting.setTabs([(index: 2, url: "https://mail.google.com/mail/u/0/#inbox")], inWindow: 7)
    scripting.resetCalls()

    _ = try await capability.open(messageID: "later@host")

    #expect(scripting.recordedFocusedTabs.map(\.window) == [7])
    #expect(scripting.recordedTabs.isEmpty) // no duplicate tab
}

@Test("an account with no matching Chrome profile still opens, via a plain Chrome open")
func mailWithoutAProfileDegradesToPlainOpen() async throws {
    let workspace = mailWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(workspace: workspace, scripting: scripting, settle: {})
    let capability = NSWorkspaceMailOpenCapability(
        workspace: workspace,
        accountAddress: { "someone@elsewhere.com" },
        profileForAccount: { _ in nil }, // no Chrome profile is signed into it
        chromeLauncher: launcher,
        currentModeProvider: { "executive" }
    )

    let result = try await capability.open(messageID: nil)

    // Opened with Chrome, but as a document — no profile could be chosen, and guessing one would
    // land the user's mail in someone else's session.
    #expect(result.opened)
    #expect(workspace.recordedLaunches.isEmpty)
    #expect(workspace.documentOpens.map(\.absoluteString) == ["https://mail.google.com/mail/u/someone@elsewhere.com/#inbox"])
}

@Test("with no Chrome installed it falls back to the default browser")
func mailWithoutChromeUsesDefaultBrowser() async throws {
    let workspace = mailWorkspace(hasChrome: false)
    let capability = NSWorkspaceMailOpenCapability(
        workspace: workspace, accountAddress: { nil }, profileForAccount: { _ in nil }
    )

    let result = try await capability.open(messageID: nil)

    #expect(result.opened)
    #expect(workspace.urlOpens.map(\.absoluteString) == [NSWorkspaceMailOpenCapability.inboxURL])
}
#endif
