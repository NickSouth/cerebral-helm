// Opening Gmail in the browser (Gmail integration, 2026-08-04).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Opens the user's Gmail — the inbox, or one message in it — in the Chrome profile that is
/// actually signed into the connected account.
///
/// **The destination host is a literal constant here**, exactly as in
/// ``NSWorkspaceGoogleSearchCapability`` and ``NSWorkspaceYouTubeSearchCapability``, and for the
/// same reason: a message id that arrived inside a report is data, and it must only ever select
/// *which message*, never *which site*.
///
/// **Why a search URL rather than a permalink** (verified 2026-08-04): Gmail's web UI addresses a
/// message by an opaque per-account id that the API never returns and that cannot be derived. The
/// API's message `id` is a different identifier and does not work in the web fragment. The reliable
/// route is `#search/rfc822msgid:<Message-ID>` — the RFC 5322 header, which is stable across
/// accounts — so the link opens Gmail filtered to exactly that one message. It is one view away
/// from the message rather than inside it; that is the best the API allows, and the surface should
/// not imply otherwise.
///
/// **Why the account is addressed by name.** `/mail/u/0/` means "the first account signed in to
/// this browser profile", not a particular mailbox — with a personal and a school account both
/// signed in, the same URL resolves to different inboxes depending on sign-in order, so a link
/// built from one inbox could open the other. `/mail/u/<address>/` names the mailbox, and the
/// address rides along with the grant it came from. Falls back to `u/0` only when no address was
/// recorded (a grant stored before this existed).
///
/// **Why the profile is derived, not configured.** Chrome's own `Local State` records which account
/// each profile is signed into, so the profile that can actually open this mail is already known —
/// asking the user to pick one would add a setting whose only correct value is computable, and
/// which would silently rot the day they re-sign-in elsewhere.
public struct NSWorkspaceMailOpenCapability: MailOpenCapability {
    private static let chromeBundleID = "com.google.Chrome"
    /// The inbox for the default account — the fallback when no address is recorded.
    static let inboxURL = "https://mail.google.com/mail/u/0/#inbox"

    private let workspace: any WorkspaceOpening
    /// The connected account's address, read from the stored grant at open time (not captured at
    /// construction: the capability is built at launch, before any account is connected).
    private let accountAddress: @Sendable () async -> String?
    /// address → Chrome profile directory, or nil when no profile is signed into it.
    private let profileForAccount: @Sendable (String) -> String?
    /// Focuses/reuses the `(mode, profile)` Chrome window (NIC-151 + NIC-143 follow-up). Nil falls
    /// back to a plain open.
    private let chromeLauncher: ChromeProfileLauncher?
    private let currentModeProvider: @Sendable () -> String?

    public init(
        workspace: any WorkspaceOpening = SystemWorkspace(),
        accountAddress: @escaping @Sendable () async -> String? = { nil },
        profileForAccount: @escaping @Sendable (String) -> String? = { _ in nil },
        chromeLauncher: ChromeProfileLauncher? = nil,
        currentModeProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.workspace = workspace
        self.accountAddress = accountAddress
        self.profileForAccount = profileForAccount
        self.chromeLauncher = chromeLauncher
        self.currentModeProvider = currentModeProvider
    }

    public func open(messageID: String?) async throws -> MailOpenResult {
        let address = await accountAddress()
        guard let url = Self.mailURL(messageID: messageID, address: address) else {
            throw NativeCapabilityError.adapterFailure("Could not build the Gmail URL.")
        }
        let profile = address.flatMap { profileForAccount($0) }

        do {
            if let chromeLauncher, let profile {
                // The profile signed into this mailbox. The launcher surfaces an existing Gmail tab
                // in that profile's window rather than stacking a new one on every link — the
                // behavior URL and app tiles already have.
                try await chromeLauncher.open(
                    mode: currentModeProvider(), profile: profile, url: url
                )
            } else if let chromeURL = workspace.installedApplicationURL(forBundleIdentifier: Self.chromeBundleID) {
                // No profile resolved (Chrome not signed into the account, or no address recorded):
                // a plain Chrome open, which lands in whichever profile is frontmost.
                try await workspace.open(paths: [url], withApplicationAt: chromeURL)
            } else {
                try await workspace.openURL(url)
            }
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch let error as NativeCapabilityError {
            throw error
        } catch {
            throw NativeCapabilityError.adapterFailure("Opening Gmail failed: \(error.localizedDescription)")
        }
        return MailOpenResult(opened: true, resolvedURL: url.absoluteString)
    }

    // MARK: - Pure helper (unit-tested)

    /// The Gmail URL for a message id, or the inbox when there is none, addressed to `address`
    /// when one is known.
    ///
    /// The id is percent-encoded into a single fragment component, so an `@`, a `+`, or anything
    /// else legal in a Message-ID cannot end the fragment early or add a second one.
    static func mailURL(messageID: String?, address: String? = nil) -> URL? {
        let account = Self.accountSegment(address)
        let inbox = "https://mail.google.com/mail/u/\(account)/#inbox"
        guard let messageID, !messageID.trimmingCharacters(in: .whitespaces).isEmpty else {
            return URL(string: inbox)
        }
        // Senders' Message-IDs are conventionally written `<id@host>`; the search operator wants
        // the bare value.
        let bare = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard let escaped = bare.addingPercentEncoding(withAllowedCharacters: Self.fragmentAllowed),
              !escaped.isEmpty
        else {
            return URL(string: inbox)
        }
        return URL(string: "https://mail.google.com/mail/u/\(account)/#search/rfc822msgid:\(escaped)")
    }

    /// The `u/<…>` segment: the account's address when known, else `0` (the default account).
    /// Encoded so an address can only ever be one path segment.
    private static func accountSegment(_ address: String?) -> String {
        guard let trimmed = address?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty,
              let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: Self.addressAllowed),
              !escaped.isEmpty
        else { return "0" }
        return escaped
    }

    /// Unreserved characters only — everything else is percent-encoded.
    private static let fragmentAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    /// As `fragmentAllowed`, plus `@` — legal in a path segment and left readable, since the URL
    /// is one the user may well look at in the address bar.
    private static let addressAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~@")
        return allowed
    }()
}
#endif
