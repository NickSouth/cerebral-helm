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

    /// Unread mail grouped into threads, each message carrying its **body**, for the email report.
    ///
    /// Separated from ``unread(limit:)`` for two reasons, not one. It reads bodies — the whole
    /// message, not a preview — which is a different and heavier read, one full fetch per message
    /// against a personal quota, so it is on-demand only and never sampled. And it groups by
    /// conversation: a report that summarises mail summarises threads, not stray messages, and the
    /// grouping belongs to the provider that knows the thread ids rather than to a consumer
    /// re-deriving it. `limit` bounds the number of THREADS; the provider bounds messages per thread
    /// and bodies at the source.
    ///
    /// Everything the same untrusted-text rules govern ``MailMessage/preview`` govern a body, only
    /// more so: a body is the largest slab of attacker-controlled text in the app, so every consumer
    /// treats it as quoted data and never as instruction, and it does not cross the bridge.
    func unreadThreads(limit: Int) async throws -> [MailThread]
}

/// A conversation's worth of unread mail, with the bodies the email report reads (NIC-258).
///
/// The unit the report composes over: one summary per thread, not per message, because a
/// back-and-forth is one thing to deal with. It holds only the messages that are actually
/// unread — the thread's read history is not fetched — so a long thread with one new reply is one
/// message here, which is what the reader cares about.
public struct MailThread: Equatable, Sendable {
    /// The provider's thread id (Gmail's `threadId`). Opaque; carried so a later action could
    /// address the conversation, never parsed.
    public let id: String
    /// The unread messages in this thread, **oldest first**, each carrying its ``MailMessage/body``.
    /// Never empty: a thread with no unread message is not assembled.
    public let messages: [MailMessage]

    public init(id: String, messages: [MailMessage]) {
        self.id = id
        self.messages = messages
    }

    /// The thread's subject — the most recent message's, since a subject can be edited on a reply
    /// and the latest wording is the one that describes where the conversation now stands.
    public var subject: String {
        messages.last?.subject ?? "(no subject)"
    }

    /// The distinct senders, in the order they first appear. A thread is "from" everyone who has
    /// written in it, and a two-person exchange reads differently from a five-person one.
    public var participants: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for message in messages where seen.insert(message.byline).inserted {
            ordered.append(message.byline)
        }
        return ordered
    }
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
/// calendar and a sprint.
///
/// ``body`` is the whole message, bounded at ``bodyLimit`` (NIC-258). It is populated only by
/// ``MailProvider/unreadThreads(limit:)`` — the email report's on-demand read — and stays nil on the
/// preview path, because the daily brief never wants a body and paying for one on a cadence would be
/// the wrong shape. It is the same untrusted text the preview is, only more of it, so the same rule
/// travels with it and matters more.
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

    /// The message body, plain text, bounded at ``bodyLimit`` (NIC-258), or nil when it was not
    /// read — which is every message on the preview path, and any message whose body could not be
    /// decoded. Absent rather than empty for the same reason ``preview`` is: an empty body and an
    /// unread one are different facts.
    public let body: String?

    /// How much of a message a preview may carry.
    ///
    /// Sized against what it is for. Gmail's own snippet runs to roughly this length, eight of them
    /// cost only a few hundred tokens beside a snapshot and a profile, and the figure is small
    /// enough that the field cannot quietly become a body: at 300 characters a reader can tell an
    /// invoice from a newsletter and cannot reconstruct the correspondence.
    public static let previewLimit = 300

    /// How much of a body the report will read — roughly 2 KB (owner decision, NIC-258).
    ///
    /// Bounded for two reasons at once. Tokens: eight full bodies would dwarf a snapshot, and the
    /// summary the model writes needs the opening of a message far more than its quoted trail. And
    /// blast radius: a body is untrusted text, so the less of it that reaches a model context, the
    /// smaller the surface for an instruction hidden inside one. Enough to summarise a real message,
    /// not enough to pull a whole newsletter into the prompt.
    public static let bodyLimit = 2048

    public init(
        id: String,
        from: String,
        subject: String,
        receivedAt: String?,
        rfc822MessageID: String?,
        preview: String? = nil,
        body: String? = nil
    ) {
        self.id = id
        self.from = from
        self.subject = subject
        self.receivedAt = receivedAt
        self.rfc822MessageID = rfc822MessageID
        self.preview = MailMessage.bounded(preview)
        self.body = MailMessage.boundedBody(body)
    }

    /// Trims and caps a preview at the source, so no caller has to remember to.
    static func bounded(_ preview: String?) -> String? { collapsed(preview, limit: previewLimit) }

    /// Trims and caps a body at ``bodyLimit`` (NIC-258), the same way and for the same reason as a
    /// preview — one function, two limits, so the two can never drift in how they collapse or cut.
    static func boundedBody(_ body: String?) -> String? { collapsed(body, limit: bodyLimit) }

    /// Collapses whitespace and caps at `limit`, at the source, so no caller has to remember to.
    ///
    /// Bounded here rather than at the surface that renders or sends it, because a limit applied
    /// late is a limit that one new caller forgets. Whitespace collapses first: mail arrives with
    /// the newlines of the original message in it, and text that spans dozens of lines costs a model
    /// more attention than the fact inside it is worth.
    static func collapsed(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        // A hard cut, with an ellipsis so a reader — or a model — can see it was cut rather than
        // that the sender stopped mid-sentence.
        return String(collapsed.prefix(limit - 1)) + "\u{2026}"
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

/// A fixed-outcome ``MailProvider`` for tests and for any build with no account attached: it
/// ignores the limit and yields the messages (or throws the error) it was constructed with.
///
/// Follows the convention every other port in this package uses — `MockCalendarProvider`,
/// `MockWeatherProvider`, `MockModelProvider`. It does not record what it was asked; a test that
/// needs that declares its own recorder.
public struct MockMailProvider: MailProvider {
    private let messages: Result<[MailMessage], MailError>
    private let summary: Result<MailUnreadSummary, MailError>
    private let threads: Result<[MailThread], MailError>

    public init(
        messages: [MailMessage],
        summary: MailUnreadSummary? = nil,
        // Supplied when a test needs real threads with bodies; otherwise each message becomes its
        // own one-message thread, which is the honest degenerate case the grouping collapses to.
        threads: [MailThread]? = nil
    ) {
        self.messages = .success(messages)
        // Defaults to a count that agrees with the listing, because the real provider derives both
        // from one query and the two cannot disagree there either.
        self.summary = .success(
            summary ?? MailUnreadSummary(count: messages.count, isCapped: false, scope: .primary)
        )
        self.threads = .success(threads ?? messages.map { MailThread(id: $0.id, messages: [$0]) })
    }

    public init(error: MailError) {
        self.messages = .failure(error)
        self.summary = .failure(error)
        self.threads = .failure(error)
    }

    public func unreadSummary() async throws -> MailUnreadSummary { try summary.get() }

    public func unread(limit: Int) async throws -> [MailMessage] {
        Array(try messages.get().prefix(max(0, limit)))
    }

    public func unreadThreads(limit: Int) async throws -> [MailThread] {
        Array(try threads.get().prefix(max(0, limit)))
    }
}
