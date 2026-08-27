// Reading the inbox through the Gmail REST API (Gmail integration, 2026-08-04).
#if canImport(AppKit)
import Foundation
import CerebralCore

/// Reads unread mail through Gmail's REST API, authenticated by ``GoogleAuthSession``.
///
/// **The count costs one request and reads no mail at all.** It is the length of a single
/// `messages.list` response, which returns bare ids — so the continuously-sampled value never
/// touches a message, never sees a subject, and cannot leak one. Fetching the messages themselves
/// is a separate, on-demand call precisely so that stays true.
///
/// That listing is also what the email report shows, which is the point: the count and the rows
/// come from **one query**, so they cannot report different mailboxes. An earlier version counted
/// with `users.labels.get('INBOX')` while listing with a filter, and the two disagreed by design.
///
/// Every request is a GET. Nothing here marks read, archives, labels, or sends; the adapter has no
/// method that could.
///
/// **What it reads of a message is headers plus Gmail's own snippet** — see ``metadataHeaders``.
/// Bodies are still never fetched: `format=metadata` returns no `payload.parts`, and nothing here
/// asks for `full` or `raw`.
public struct GmailAPIProvider: MailProvider {
    /// Headers worth asking for. `format=metadata` with an explicit allowlist means Gmail returns
    /// only these headers, and never the message body: `payload.parts` is absent under this format,
    /// so no body text can end up in memory, a log, or a report.
    ///
    /// `Message-ID` is here so a report row can link to the message: Gmail's web UI addresses mail
    /// by an opaque per-account id the API never returns, and the RFC 5322 header is the only
    /// stable handle there is.
    ///
    /// **A preview comes back alongside these, and that is now wanted** (owner decision,
    /// 2026-08-26). `snippet` is a top-level field of the Message resource rather than part of
    /// `payload`, so it is unaffected by the header allowlist. Reading it is a decision, not an
    /// accident: the daily brief is asked to say which mail needs the reader, and a subject line
    /// alone cannot support that judgement. The format stays `metadata`, so this remains the only
    /// message text the adapter can see — a preview, not a body. See ``MailMessage/preview``.
    static let metadataHeaders = ["From", "Subject", "Date", "Message-ID"]

    /// Gmail's Primary tab. Its inbox categories are system labels (`CATEGORY_PERSONAL`,
    /// `_SOCIAL`, `_PROMOTIONS`, `_UPDATES`, `_FORUMS`), and the personal one is Primary.
    static let primaryCategoryLabel = "CATEGORY_PERSONAL"

    /// How far the sampled count will actually count.
    ///
    /// The count is the length of a single id listing, which is exact — but only up to the number
    /// of ids asked for (`maxResults`, capped at 500 by Gmail). A hundred is far past the point
    /// where a dashboard number stops being read as a quantity and starts being read as "a lot",
    /// and it keeps the recurring request small. Past it the summary says `isCapped` rather than
    /// pretending the ceiling is the total.
    ///
    /// `resultSizeEstimate` is deliberately not used for this: Google documents it as an estimate,
    /// and a count on a dashboard should not be a guess.
    static let countCeiling = 100

    private let session: GoogleAuthSession
    private let urlSession: URLSession
    private let host: String

    public init(
        session: GoogleAuthSession,
        urlSession: URLSession? = nil,
        host: String = "https://gmail.googleapis.com",
        resourceTimeout: TimeInterval = 20
    ) {
        self.session = session
        self.host = host
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.urlSession = URLSession(configuration: config)
        }
    }

    public func unreadSummary() async throws -> MailUnreadSummary {
        let (ids, scope) = try await unreadMessageIDs(limit: Self.countCeiling)
        return MailUnreadSummary(
            count: ids.count, isCapped: ids.count >= Self.countCeiling, scope: scope
        )
    }

    public func unread(limit: Int) async throws -> [MailMessage] {
        let capped = max(1, min(limit, 25))
        let (ids, _) = try await unreadMessageIDs(limit: capped)
        guard !ids.isEmpty else { return [] }

        // Sequential rather than concurrent: this runs on demand for at most 25 messages, and a
        // burst of parallel requests against a personal quota buys milliseconds at the cost of
        // being the noisiest client on the account.
        var messages: [MailMessage] = []
        for id in ids {
            let detail = try await get(
                path: "/gmail/v1/users/me/messages/\(id)",
                query: [URLQueryItem(name: "format", value: "metadata")]
                    + Self.metadataHeaders.map { URLQueryItem(name: "metadataHeaders", value: $0) }
            )
            // A message that will not parse is dropped rather than failing the list: one odd item
            // must not cost the user the whole report.
            if let message = Self.parseMessage(detail) { messages.append(message) }
        }
        return messages
    }

    // MARK: - Selecting the unread mail that matters

    /// Unread message ids, newest first, and which slice they came from.
    ///
    /// **One query serves both the count and the listing**, so the two cannot disagree: the count
    /// is the length of this list, not a separately-fetched total that filters differently.
    ///
    /// `labelIds` are combined with AND (verified against Google's `messages.list` reference), so
    /// `INBOX + UNREAD + CATEGORY_PERSONAL` is exactly "unread in the Primary tab". `labelIds` is
    /// used rather than `q=is:unread category:primary` because it survives every scope — the
    /// tighter `gmail.metadata` forbids `q` outright — so narrowing the grant later would not need
    /// this rewritten.
    ///
    /// **An empty Primary means "you are caught up" — not "the filter must be broken".**
    ///
    /// An earlier version treated any empty Primary result as evidence that the account did not
    /// categorize, and fell back to the whole inbox. On an account that keeps up with personal mail
    /// and lets promotions pile up, that is exactly backwards: it answers "nothing unread that
    /// matters" with a hundred promotional messages, defeating the filter at the one moment it was
    /// working perfectly. Verified against the owner's own account, where it did precisely that.
    ///
    /// The two cases are now distinguished by asking, rather than inferred: does this account
    /// categorize at all? An account with inbox categories off has never applied
    /// `CATEGORY_PERSONAL` to anything, so its total is zero — and only then is the whole inbox the
    /// honest answer, because otherwise the filter would report an empty inbox forever. The extra
    /// request happens only when Primary is empty, which is the cheap case by definition.
    private func unreadMessageIDs(limit: Int) async throws -> (ids: [String], scope: MailUnreadScope) {
        let primary = try await listUnreadIDs(limit: limit, primaryOnly: true)
        if !primary.isEmpty {
            return (primary, .primary)
        }
        if try await accountCategorizes() {
            return ([], .primary)
        }
        // No categories on this account: the filtered query can never match, so the plain inbox is
        // the only honest answer. Reported as `.inbox` so the surface stops claiming "Primary".
        return (try await listUnreadIDs(limit: limit, primaryOnly: false), .inbox)
    }

    /// Whether this account applies Gmail's inbox categories.
    ///
    /// `messagesTotal` on the Primary label rather than the label's mere existence: a system label
    /// may be listed on an account that never uses it, and what actually matters is whether
    /// anything has ever been categorized. A read failure answers **true** — the safe direction,
    /// since the alternative is falling back to an unfiltered inbox on a transient error and
    /// burying the user in the promotions they asked to be rid of.
    private func accountCategorizes() async -> Bool {
        guard let data = try? await get(path: "/gmail/v1/users/me/labels/\(Self.primaryCategoryLabel)"),
              let total = Self.parseLabelTotal(data)
        else { return true }
        return total > 0
    }

    private func listUnreadIDs(limit: Int, primaryOnly: Bool) async throws -> [String] {
        var query = [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "labelIds", value: "UNREAD")
        ]
        if primaryOnly {
            query.append(URLQueryItem(name: "labelIds", value: Self.primaryCategoryLabel))
        }
        query.append(URLQueryItem(name: "maxResults", value: String(limit)))
        let data = try await get(path: "/gmail/v1/users/me/messages", query: query)
        guard let ids = Self.parseMessageIDs(data) else {
            throw MailError.providerFailed("Gmail's message list was not in the shape we read.")
        }
        return ids
    }

    // MARK: - Requests

    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let token: String
        do {
            token = try await session.accessToken()
        } catch let error as GoogleAuthError {
            throw Self.mailError(for: error)
        }
        guard var components = URLComponents(string: host + path) else {
            throw MailError.providerFailed("Could not build the Gmail request.")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw MailError.providerFailed("Could not build the Gmail request.")
        }
        var request = URLRequest(url: url)
        // The token rides the Authorization header, never the URL, so it cannot leak through a
        // logged request description (FR-OBS-03).
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw MailError.providerFailed("Cancelled.")
        } catch {
            throw MailError.providerFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, let error = Self.mailError(forStatus: http.statusCode) {
            throw error
        }
        return data
    }

    // MARK: - Account identity

    /// The connected account's own address, read once at connect from `users.getProfile`.
    ///
    /// Standalone and token-taking rather than a method on the provider, because the only caller is
    /// the auth coordinator, which holds a freshly exchanged token and no session yet.
    ///
    /// Returns nil on any failure **by design**: the address makes a link land in the right account
    /// and the right Chrome profile, which is a refinement — failing a connect the user just
    /// completed, over it, would trade a working integration for a cosmetic one.
    public static func fetchAddress(
        accessToken: String, host: String = "https://gmail.googleapis.com",
        urlSession: URLSession = .shared
    ) async -> String? {
        guard let url = URL(string: host + "/gmail/v1/users/me/profile") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard
            let (data, response) = try? await urlSession.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return parseAddress(data)
    }

    /// `emailAddress` from a profile response.
    static func parseAddress(_ data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let address = root["emailAddress"] as? String,
            !address.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return address
    }

    // MARK: - Pure parsing (unit-tested)

    /// `401` is a rejected token — the grant lapsed, so reconnect. `403` on Gmail is usually the
    /// API not being enabled on the project, or a scope the grant does not carry; both are
    /// configuration rather than a lapsed grant, and saying "reconnect" would send the user in
    /// circles the way the token-exchange bug did.
    static func mailError(forStatus statusCode: Int) -> MailError? {
        switch statusCode {
        case 200..<300:
            return nil
        case 401:
            return .reconnectRequired
        case 403:
            return .providerFailed("Gmail refused the request — check the Gmail API is enabled and the grant covers reading mail.")
        case 429:
            return .providerFailed("Gmail's rate limit was reached. Try again shortly.")
        default:
            return .providerFailed("Gmail returned HTTP \(statusCode).")
        }
    }

    static func mailError(for error: GoogleAuthError) -> MailError {
        switch error {
        case .clientIDMissing, .notConnected: return .notConnected
        case .cancelled: return .providerFailed("Cancelled.")
        case let .providerFailed(detail): return .providerFailed(detail)
        }
    }

    /// A label's total message count, or nil when the body is not that label's resource. The id is
    /// checked for the same reason the list parser checks its shape: an error object must not read
    /// as "this label holds nothing".
    static func parseLabelTotal(_ data: Data, id: String = GmailAPIProvider.primaryCategoryLabel) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["id"] as? String == id
        else { return nil }
        // Gmail omits the counts for a label holding nothing, which is itself a real zero.
        return root["messagesTotal"] as? Int ?? 0
    }

    /// Message ids from a list response, or **nil when the response is not one**.
    ///
    /// The distinction carries the whole honesty of the count, which is now the length of this
    /// array: a body that does not parse must not come back as an empty list, because empty means
    /// "your inbox is clear" and would be a calm, confident lie. A genuinely empty result is a real
    /// JSON object with no `messages` key (Gmail omits it), and only that reads as zero.
    static func parseMessageIDs(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let messages = root["messages"] as? [[String: Any]] {
            return messages.compactMap { $0["id"] as? String }
        }
        // No `messages` key. That is what Gmail returns for a genuinely empty result — but only
        // alongside `resultSizeEstimate`, which every list response carries. Requiring it is the
        // same guard the label read used (`id == "INBOX"`): it is what stops an error object, or a
        // shape change, from being counted as an inbox with nothing in it.
        return root["resultSizeEstimate"] != nil ? [] : nil
    }

    /// One message from a metadata response. Header names are matched **case-insensitively**: the
    /// RFC makes them case-insensitive and Gmail echoes whatever the sender wrote.
    static func parseMessage(_ data: Data) -> MailMessage? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = root["id"] as? String
        else { return nil }
        let headers = (root["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
        func header(_ name: String) -> String? {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
        }
        return MailMessage(
            id: id,
            // A message with neither is still a message; naming the gap beats dropping the row.
            from: header("From") ?? "Unknown sender",
            subject: header("Subject") ?? "(no subject)",
            // `internalDate` — when Gmail RECEIVED the message — in preference to the `Date`
            // header, which is whatever the sender's machine claimed. Two reasons, both visible on
            // screen: the list is ordered by internalDate, so showing header times produced rows
            // whose timestamps ran backwards; and the header is free-form, so a sender writing
            // `+0000 (UTC)` or a named zone parsed to nothing and the row lost its time entirely.
            // internalDate is a plain epoch and is always present.
            receivedAt: Self.parseInternalDate(root["internalDate"])
                ?? header("Date").flatMap(Self.parseRFC2822),
            rfc822MessageID: header("Message-ID")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")),
            // Gmail's own preview of the message text. A TOP-LEVEL field of the Message resource,
            // not part of `payload`, so the header allowlist above does not govern it.
            //
            // Note that Google's reference describes `metadata` as returning "only email message
            // ID, labels, and email headers" and does not list `snippet` among them. Read
            // defensively for that reason: absent is a normal outcome here, never an error, and a
            // brief composed without previews is a thinner brief rather than a broken one. The
            // live probe in GmailAPIProviderTests is what settles which way this account behaves.
            preview: root["snippet"] as? String
        )
    }

    /// Gmail's `internalDate` — milliseconds since the epoch, as the JSON string an int64 maps to
    /// (a raw number is accepted too, since that mapping is a serialization detail rather than
    /// something worth breaking a timestamp over).
    static func parseInternalDate(_ value: Any?) -> String? {
        let milliseconds: Int64?
        switch value {
        case let text as String: milliseconds = Int64(text)
        case let number as NSNumber: milliseconds = number.int64Value
        default: milliseconds = nil
        }
        guard let milliseconds else { return nil }
        return ISO8601DateFormatter().string(
            from: Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        )
    }

    /// RFC 2822 dates as Gmail sends them (`Tue, 04 Aug 2026 13:20:00 -0400`), normalized to
    /// ISO-8601. The fallback for a message with no `internalDate`; it is deliberately strict, and
    /// a header it cannot read yields nil rather than a guessed timestamp.
    static func parseRFC2822(_ value: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return ISO8601DateFormatter().string(from: date)
            }
        }
        return nil
    }
}
#endif
