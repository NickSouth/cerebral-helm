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
/// **Headers, plus a short preview (owner decision, 2026-08-26.)** This type used to be headers
/// only, on the principle that the capability the user granted was broader than the capability the
/// code gave itself. That was deliberate and it has been deliberately overturned: the daily brief
/// is asked to say which mail needs the reader, and sender-and-subject is not enough to judge that.
///
/// What changed is the amount, not the principle. ``preview`` is a **preview, never the message**,
/// bounded at ``previewLimit`` — enough to tell an invoice from a newsletter, not enough to
/// reconstruct correspondence, and cheap enough that eight of them fit a context window beside a
/// calendar and a sprint. Reading whole bodies remains unbuilt.
///
/// Two rules travel with it. It is **untrusted text**: anyone who can email the user can put words
/// in front of a model through this field, so every consumer treats it as quoted data and never as
/// instruction. And it **does not cross the bridge** — the composer runs host-side, so no preview
/// reaches the web layer, and `UnreadMailItem` still carries subject and byline alone.
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
    /// A short excerpt of the message text, bounded at ``previewLimit``, or nil when the provider
    /// supplied none. Absent rather than empty when unavailable: "there was no preview" and "the
    /// message opens with nothing" are different facts, and a composer told the second would
    /// describe an empty email.
    public let preview: String?

    /// How much of a message a preview may carry.
    ///
    /// Sized against what it is for. Gmail's own snippet runs to roughly this length, eight of them
    /// cost only a few hundred tokens beside a snapshot and a profile, and the figure is small
    /// enough that the field cannot quietly become a body: at 300 characters a reader can tell an
    /// invoice from a newsletter and cannot reconstruct the correspondence.
    public static let previewLimit = 300

    public init(
        id: String,
        from: String,
        subject: String,
        receivedAt: String?,
        rfc822MessageID: String?,
        preview: String? = nil
    ) {
        self.id = id
        self.from = from
        self.subject = subject
        self.receivedAt = receivedAt
        self.rfc822MessageID = rfc822MessageID
        self.preview = MailMessage.bounded(preview)
    }

    /// Trims and caps a preview at the source, so no caller has to remember to.
    ///
    /// Bounded here rather than at the surface that renders or sends it, because a limit applied
    /// late is a limit that one new caller forgets. Whitespace collapses first: Gmail's snippets
    /// arrive with the newlines of the original message in them, and a preview that spans six lines
    /// costs a model more attention than the fact inside it is worth.
    static func bounded(_ preview: String?) -> String? {
        guard let preview else { return nil }
        let collapsed = preview.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > previewLimit else { return collapsed }
        // A hard cut, with an ellipsis so a reader — or a model — can see it was cut rather than
        // that the sender stopped mid-sentence.
        return String(collapsed.prefix(previewLimit - 1)) + "\u{2026}"
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
