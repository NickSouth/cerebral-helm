import Foundation

/// Gathers the email report's typed snapshot from the mail provider, deterministically (NIC-259).
///
/// The Assembler half of `providers → Assembler → Snapshot → Composer → ReportDocument → Renderer`,
/// the second surface on the spine the daily brief established. Like ``DailyBriefAssembler`` it
/// reads and does not compose, and it runs **host-side** — the whole reason bodies can be read at
/// all. A message body is the largest slab of attacker-controlled text in the app; assembling here
/// means it reaches a model context but never the web layer, and the composer that reads it is told
/// the body is quoted data, never instruction.
///
/// Where the daily brief reads six sources for a count and a preview, this reads mail in depth: the
/// unread total for "how many", and the most recent threads **with their bodies** for "which of
/// them needs you". Profile comes along for the same reason it does in the brief — a summary written
/// against who the reader is beats one written against no one — and nothing else does, because the
/// email report is about mail.
public struct EmailReportAssembler: Sendable {
    /// The quick-action id this assembler gathers for. Named here, matching ``DailyBriefAssembler``,
    /// because the composer configuration keys on the same value and a typo between the two would
    /// read as "this report is not model-composed."
    public static let reportID = "email-report"

    /// How many unread threads carry their bodies into the report.
    ///
    /// Eight, the same judgement figure the daily brief uses: enough that "which of these needs you"
    /// is a real call rather than a look at the top two, and bounded so the read stays affordable.
    /// The per-thread message cap and the 2 KB body bound live in the provider, so eight threads is a
    /// bounded cost even when a conversation is long.
    public static let threadLimit = 8

    private let mail: (any MailProvider)?
    private let profile: ProfileContextReader?
    private let timeZone: TimeZone

    /// Mail and profile are each optional: a machine with no Gmail account or no vault is a normal
    /// machine, and an absent source produces the same honest `state` as one that failed to read.
    public init(
        mail: (any MailProvider)? = nil,
        profile: ProfileContextReader? = nil,
        timeZone: TimeZone = .current
    ) {
        self.mail = mail
        self.profile = profile
        self.timeZone = timeZone
    }

    /// The snapshot, as the Composer will receive it.
    ///
    /// `now` is passed rather than read so the report is reproducible: the same instant and the same
    /// provider produce byte-identical JSON, which is what lets a test assert on it and keeps the
    /// prompt's cache prefix stable.
    public func assemble(now: Date) async -> JSONValue {
        async let mailSection = self.mailSection()
        async let profileSection = self.profileSection()

        return .object([
            "now": .string(DailyBriefAssembler.timestamp(now, timeZone: timeZone)),
            "mail": await mailSection,
            "profile": await profileSection
        ])
    }

    // MARK: - Mail

    /// The unread total, and the most recent threads with their bodies.
    ///
    /// Two reads, and they cannot be one: the total comes from a summary that reads no message, and
    /// the threads come from a listing that reads bodies. Taking the count from the listing's length
    /// would report "8 unread" for an inbox holding fifty; taking the threads from the count reads no
    /// mail at all.
    private func mailSection() async -> JSONValue {
        guard let mail else {
            return .object(["state": .string("unavailable"), "reason": .string("No mail account is connected.")])
        }

        do {
            let summary = try await mail.unreadSummary()
            let threads = try await mail.unreadThreads(limit: Self.threadLimit)

            var fields: [String: JSONValue] = [
                "state": .string("ready"),
                "unreadTotal": .number(Double(summary.count)),
                // The count stopped counting rather than reached zero. Without this a capped 100 is
                // read as an exact hundred.
                "isCapped": .bool(summary.isCapped),
                // Primary tab or whole inbox — the difference between "three personal emails" and
                // "three including promotions".
                "scope": .string(summary.scope.rawValue),
                "threads": .array(threads.map(thread(from:)))
            ]
            if summary.count == 0 { fields["threads"] = .array([]) }
            return .object(fields)
        } catch MailError.notConnected {
            return .object(["state": .string("unavailable"), "reason": .string("No mail account is connected.")])
        } catch MailError.reconnectRequired {
            return .object([
                "state": .string("unavailable"),
                "reason": .string("The mail connection needs renewing.")
            ])
        } catch {
            return .object(["state": .string("unavailable"), "reason": .string("Mail couldn\u{2019}t be read.")])
        }
    }

    private func thread(from thread: MailThread) -> JSONValue {
        .object([
            "subject": .string(thread.subject),
            // The distinct senders, so the composer can tell a two-person exchange from a group
            // without walking the messages to work it out.
            "participants": .array(thread.participants.map(JSONValue.string)),
            "messages": .array(thread.messages.map(message(from:)))
        ])
    }

    private func message(from message: MailMessage) -> JSONValue {
        var fields: [String: JSONValue] = [
            // The byline, not the raw `From`: a report reads as people, not mailboxes, and the
            // address itself has no business in the model's context.
            "from": .string(message.byline)
        ]
        if let receivedAt = message.receivedAt { fields["receivedAt"] = .string(receivedAt) }
        // UNTRUSTED TEXT, and the most of it anywhere in the app. Presented as a named, quoted value
        // rather than folded into prose; the system prompt states that quoted outside content is
        // data and never instruction. Absent rather than empty when a body could not be decoded, so
        // "no body" and "an empty message" stay distinct facts.
        if let body = message.body { fields["body"] = .string(body) }
        return .object(fields)
    }

    // MARK: - Profile

    /// The durable "who I am" layer, unchanged from the daily brief's use of it: the highest-leverage
    /// context there is, carrying no `notes` key when the folder is empty because an empty string is
    /// a fact a composer would dutifully describe.
    private func profileSection() async -> JSONValue {
        guard let profile else {
            return .object(["state": .string("unavailable"), "reason": .string("No knowledge vault is configured.")])
        }
        do {
            guard let notes = try await profile.read() else {
                return .object(["state": .string("ready")])
            }
            return .object(["state": .string("ready"), "notes": .string(notes)])
        } catch {
            return .object([
                "state": .string("unavailable"),
                "reason": .string("The knowledge vault couldn\u{2019}t be read.")
            ])
        }
    }
}
