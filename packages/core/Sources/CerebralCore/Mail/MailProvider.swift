/// Reading the user's mailbox (Gmail integration, 2026-08-04).
///
/// A **read-only** port by construction: nothing here sends, archives, marks read, or modifies a
/// label. That is not merely the current requirement — a mail port that could write would put the
/// most consequential capability in the app behind the same seam as a widget refresh.
///
/// Deliberately provider-neutral. Gmail is the first implementation and the only planned one, but
/// the surfaces above (a count in the daily brief, a list in the email report) describe mail, not
/// Gmail, and would be identical over any account.
public protocol MailProvider: Sendable {
    /// How much unread mail is waiting.
    ///
    /// Separated from ``unread(limit:)`` because it is **dramatically cheaper** — it identifies
    /// messages without reading any of them — and because it is the thing a dashboard samples
    /// continuously, where fetching message contents on a cadence would be the wrong shape.
    ///
    /// It must count the **same slice** ``unread(limit:)`` lists. A count and a list drawn from
    /// different filters is the failure this port exists to prevent: five rows under a count of
    /// forty, with no way for the reader to tell which one is lying.
    func unreadSummary() async throws -> MailUnreadSummary

    /// The unread messages themselves, newest first, for a surface that lists them. Costs one
    /// request per message, so this is on-demand only — never sampled on a cadence.
    func unread(limit: Int) async throws -> [MailMessage]
}

/// Which slice of the mailbox a count and a listing cover.
///
/// Promotional mail is the bulk of an ordinary inbox and almost none of its meaning, so the default
/// slice is the primary one. The distinction is carried rather than assumed because the *number*
/// differs enormously between them, and a surface showing "12 unread" when 340 are waiting is
/// telling the user something false about their own mailbox.
public enum MailUnreadScope: String, Equatable, Sendable {
    /// The primary slice — personal correspondence, with promotions/social/updates excluded.
    case primary
    /// The whole inbox, because the provider does not categorize it (the user turned categories
    /// off, or the account never had them). Reported honestly rather than silently returning
    /// nothing, which would read as an empty inbox.
    case inbox
}

/// How much unread mail is waiting.
public struct MailUnreadSummary: Equatable, Sendable {
    /// Unread messages in ``scope``. Zero is a real, meaningful answer — an empty inbox — and must
    /// never be confused with "we could not ask", which is an error rather than a count.
    public let count: Int
    /// True when counting stopped at a ceiling: there are **at least** `count`, and the exact total
    /// was not measured. A surface must render this as "100+" rather than as a precise number it
    /// was never given.
    public let isCapped: Bool
    /// What was counted, so a surface can say so instead of implying it counted everything.
    public let scope: MailUnreadScope

    public init(count: Int, isCapped: Bool = false, scope: MailUnreadScope = .primary) {
        self.count = count
        self.isCapped = isCapped
        self.scope = scope
    }
}

/// One message, as far as a report needs to describe it.
///
/// **Headers only, deliberately.** The grant allows reading bodies; this type cannot carry one, so
/// no surface above it can accidentally render or log the contents of an email. The capability the
/// user granted is broader than the capability this code gives itself.
public struct MailMessage: Equatable, Sendable {
    public let id: String
    /// The sender as Gmail reports it — usually `Display Name <address@host>`.
    public let from: String
    public let subject: String
    /// When it arrived, ISO-8601. Nil when the header is missing or unparseable, which is rare and
    /// reported as absent rather than guessed at.
    public let receivedAt: String?
    /// The RFC 5322 `Message-ID`, without angle brackets — the only handle that can address this
    /// message in a mail client's web UI. Gmail's own web id is opaque, per-account, and never
    /// returned by its API, so this is what a link is built from. Nil when the sender omitted it,
    /// in which case the row simply is not a link.
    public let rfc822MessageID: String?

    public init(
        id: String, from: String, subject: String, receivedAt: String?, rfc822MessageID: String?
    ) {
        self.id = id
        self.from = from
        self.subject = subject
        self.receivedAt = receivedAt
        self.rfc822MessageID = rfc822MessageID
    }

    /// The sender's display name where there is one — "Mum" from `Mum <mum@example.com>` — else
    /// the bare address. A byline reads as a person, not a mailbox.
    public var byline: String {
        // Trimmed without Foundation so this file stays importable wherever Core is.
        func strip(_ value: Substring, of characters: String) -> String {
            String(value.drop { characters.contains($0) }
                .reversed().drop { characters.contains($0) }.reversed())
        }
        guard let bracket = from.firstIndex(of: "<") else { return from }
        let name = strip(from[from.startIndex..<bracket], of: " \"")
        return name.isEmpty ? strip(from[bracket...], of: "<> ") : name
    }
}

/// Why the mailbox could not be read. Each case has a different remedy, which is the whole reason
/// they are separate: connect, reconnect, or wait.
public enum MailError: Error, Equatable, Sendable {
    /// No account connected yet.
    case notConnected
    /// The grant lapsed — an expired refresh token (routine on a project in Google's "Testing"
    /// publishing status) or one revoked by a password change. The remedy is to reconnect.
    case reconnectRequired
    case providerFailed(String)
}
