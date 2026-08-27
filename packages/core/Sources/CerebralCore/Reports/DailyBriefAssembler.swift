import Foundation

/// Gathers the daily brief's typed snapshot from the providers, deterministically (NIC-228).
///
/// The Assembler half of `providers → Assembler → Snapshot → Composer → ReportDocument → Renderer`.
/// It reads; it does not compose. Everything here is a plain read of a port plus a shape — no
/// judgement, no prose, and nothing a model influences.
///
/// **It runs host-side, and the snapshot never crosses the bridge.** The dashboard's own assembler
/// keeps composing the deterministic header (greeting, date, weather), which is what lets that much
/// render instantly while the body is still being written. Everything the model reads is gathered
/// here instead, so a message preview or a profile note has no path into the web layer at all.
///
/// **Every source is read independently and fails independently.** A section carries its own
/// `state`, and an unreadable one says so rather than being omitted: the composer is instructed to
/// use only what the snapshot contains, so a missing `calendar` key and an empty calendar would be
/// indistinguishable to it — and "nothing scheduled today" is a lie when nobody could look. This is
/// the same distinction the deterministic composer draws between an empty calendar and an
/// unavailable one, carried forward to a reader that cannot infer it.
public struct DailyBriefAssembler: Sendable {
    /// How many unread messages carry a preview into the brief.
    ///
    /// Eight is what fits the job on both sides. It is enough that "anything that needs you" is a
    /// real judgement rather than a look at the top two, and at Gmail's measured ~200-character
    /// snippets it costs roughly 400 tokens — affordable beside a calendar, a sprint and a profile
    /// in a 16K window. It is also eight `messages.get` requests against a personal quota, which is
    /// why it is a small number rather than a generous one.
    public static let recentMailLimit = 8

    private let calendar: (any CalendarProvider)?
    private let mail: (any MailProvider)?
    private let timeZone: TimeZone

    /// Providers are individually optional, because a machine with no calendar grant or no Gmail
    /// account is a normal machine. An absent provider produces the same honest `state` as one that
    /// failed to read — the reader is told nobody looked, either way.
    public init(
        calendar: (any CalendarProvider)? = nil,
        mail: (any MailProvider)? = nil,
        timeZone: TimeZone = .current
    ) {
        self.calendar = calendar
        self.mail = mail
        self.timeZone = timeZone
    }

    /// The snapshot, as the Composer will receive it.
    ///
    /// `now` is passed rather than read so a brief is reproducible: the same instant and the same
    /// providers produce byte-identical JSON, which is what lets a test assert on it and what keeps
    /// the prompt's cache prefix stable.
    public func assemble(now: Date) async -> JSONValue {
        // Read concurrently: these are two independent network round trips, and running them in
        // series would add the calendar's latency to the mail's for no reason. Each still fails on
        // its own.
        async let calendarSection = self.calendarSection(now: now)
        async let mailSection = self.mailSection()

        return .object([
            "now": .string(Self.timestamp(now, timeZone: timeZone)),
            "dayOfWeek": .string(Self.weekday(now, timeZone: timeZone)),
            "calendar": await calendarSection,
            "mail": await mailSection
        ])
    }

    // MARK: - Calendar

    /// Today's and tomorrow's events, from now onward.
    ///
    /// **Two days, and unfiltered by mode.** Both differ deliberately from the dashboard's live
    /// schedule, which reads now → end of *today* and then filters to the active mode's calendar
    /// profile. Neither is right for a brief: tomorrow morning's 8am is something to know about
    /// tonight, and a morning brief that hid personal appointments because Developer mode was
    /// active would be worse than useless. The window starts at `now` rather than at midnight
    /// because a brief is about what is ahead.
    private func calendarSection(now: Date) async -> JSONValue {
        guard let calendar else {
            return .object(["state": .string("unavailable"), "reason": .string("No calendar is connected.")])
        }

        var reference = Calendar(identifier: .gregorian)
        reference.timeZone = timeZone
        let startOfToday = reference.startOfDay(for: now)
        guard
            let startOfTomorrow = reference.date(byAdding: .day, value: 1, to: startOfToday),
            let endOfTomorrow = reference.date(byAdding: .day, value: 2, to: startOfToday)
        else {
            return .object(["state": .string("unavailable"), "reason": .string("The dates could not be resolved.")])
        }

        let events: [CalendarEvent]
        do {
            events = try await calendar.events(within: DateInterval(start: now, end: endOfTomorrow))
        } catch CalendarError.permissionDenied {
            return .object([
                "state": .string("unavailable"),
                "reason": .string("Calendar access hasn\u{2019}t been granted.")
            ])
        } catch {
            return .object([
                "state": .string("unavailable"),
                "reason": .string("The calendar couldn\u{2019}t be read.")
            ])
        }

        // Bucketed by OVERLAP, not by start: an event running across midnight, and an all-day event
        // spanning both days, belong to both days — and a reader asking "what do I have tomorrow"
        // is not helped by an answer that files it under today alone.
        func overlaps(_ event: CalendarEvent, from: Date, to: Date) -> Bool {
            let end = event.end ?? event.start
            return event.start < to && end >= from
        }

        let sorted = events.sorted { $0.start < $1.start }
        return .object([
            "state": .string("ready"),
            "today": .array(sorted
                .filter { overlaps($0, from: startOfToday, to: startOfTomorrow) }
                .map { event(from: $0, reference: reference) }),
            "tomorrow": .array(sorted
                .filter { overlaps($0, from: startOfTomorrow, to: endOfTomorrow) }
                .map { event(from: $0, reference: reference) })
        ])
    }

    private func event(from event: CalendarEvent, reference: Calendar) -> JSONValue {
        var fields: [String: JSONValue] = [
            "title": .string(event.title),
            "calendar": .string(event.calendarTitle)
        ]
        if event.isAllDay {
            // No clock time on an all-day event: rendering one would invent a precision the event
            // does not have, and "Birthday at 00:00" is how that reads.
            fields["allDay"] = .bool(true)
        } else {
            fields["start"] = .string(Self.clock(event.start, reference: reference))
            if let end = event.end {
                fields["end"] = .string(Self.clock(end, reference: reference))
            }
        }
        // Omitted rather than empty when unset — the composer is told to use only what is present,
        // and an empty string is something for it to dutifully mention.
        if let location = event.location, !location.isEmpty {
            fields["location"] = .string(location)
        }
        // `notes` is deliberately NOT carried. It is read by the relevance resolver to find a
        // `#[mode]` tag and is never surfaced; a calendar description is free text a model would
        // have no reason to be trusted with and every reason to quote.
        return .object(fields)
    }

    // MARK: - Mail

    /// The unread count, and the most recent few with their previews.
    ///
    /// Two reads: a summary for the total and a listing for the messages. The count cannot be taken
    /// from the listing's length — that would report "8 unread" for an inbox holding fifty — and
    /// the listing cannot be taken from the count, which reads no message at all.
    private func mailSection() async -> JSONValue {
        guard let mail else {
            return .object(["state": .string("unavailable"), "reason": .string("No mail account is connected.")])
        }

        do {
            let summary = try await mail.unreadSummary()
            let recent = try await mail.unread(limit: Self.recentMailLimit)

            var fields: [String: JSONValue] = [
                "state": .string("ready"),
                "unreadTotal": .number(Double(summary.count)),
                // The count stopped counting rather than reached zero. Without this a capped 100 is
                // read as an exact hundred.
                "isCapped": .bool(summary.isCapped),
                // Whether this is the Primary tab or the whole inbox — the difference between "you
                // have three personal emails" and "you have three including promotions".
                "scope": .string(summary.scope.rawValue),
                "recent": .array(recent.map(message(from:)))
            ]
            if summary.count == 0 { fields["recent"] = .array([]) }
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

    private func message(from message: MailMessage) -> JSONValue {
        var fields: [String: JSONValue] = [
            // The byline, not the raw `From`: a brief reads as people, not mailboxes. It also keeps
            // the address itself out of the model's context, which nothing here needs.
            "from": .string(message.byline),
            "subject": .string(message.subject)
        ]
        if let receivedAt = message.receivedAt { fields["receivedAt"] = .string(receivedAt) }
        // UNTRUSTED TEXT. Anyone who can email the user can put words in this field, so it is
        // presented as a named, quoted value rather than folded into prose, and the system prompt
        // states that quoted outside content is data and never instruction.
        if let preview = message.preview { fields["preview"] = .string(preview) }
        return .object(fields)
    }

    // MARK: - Formatting

    /// A fixed English formatter, deliberately not the user's locale.
    ///
    /// Two reasons, both structural rather than aesthetic. The prompt is English, so a weekday in
    /// another language would be a word the model has to translate before it can reason about it.
    /// And each distinct prompt prefix is a distinct prefix-cache entry: a snapshot whose shape
    /// shifted with a locale change would quietly halve a cache measured at 98.7% in steady state.
    private static let promptLocale = Locale(identifier: "en_US_POSIX")

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = promptLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = promptLocale
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// 24-hour wall clock. Unambiguous to read and to render: the system prompt tells the model
    /// these are local wall-clock times and to say them the way a person would, so "17:30" becomes
    /// "5:30" in the brief without the snapshot having to guess at a convention.
    static func clock(_ date: Date, reference: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = promptLocale
        formatter.timeZone = reference.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
