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
/// **Two reads of a message, at two depths.** The sampled count and the daily brief's list use
/// `format=metadata` — headers plus Gmail's own snippet, never a body (see ``metadataHeaders``). The
/// email report's ``unreadThreads(limit:)`` reads `format=full` and decodes the body (NIC-258),
/// on demand only and never on a cadence. Both stay within the granted `gmail.readonly` scope; the
/// body is untrusted text, bounded and handled as such inside ``MailMessage``.
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

    /// How many unread messages of a single thread the email report reads.
    ///
    /// A conversation's most recent turns are what the reader needs; the older ones are context they
    /// already have. Capped so one runaway thread cannot become the whole report — the bound on
    /// bodies is per message, so a thread with no cap is a hole in the token budget — and small
    /// because each message is one more full fetch against a personal quota.
    static let maxMessagesPerThread = 3

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

    public func unreadThreads(limit: Int) async throws -> [MailThread] {
        let cappedThreads = max(1, min(limit, 15))
        // List enough messages to fill the threads even if the first few conversations are chatty.
        // The list is already the unread slice, so grouping it by thread yields exactly the unread
        // messages of each — the read history is never fetched.
        let (refs, _) = try await unreadMessageRefs(limit: cappedThreads * Self.maxMessagesPerThread)
        guard !refs.isEmpty else { return [] }

        // Group preserving newest-first thread order: the list is newest-first, so a thread first
        // appears at its newest message, and iterating in that order ranks the threads the way the
        // reader would.
        var order: [String] = []
        var byThread: [String: [MessageRef]] = [:]
        for ref in refs {
            if byThread[ref.threadId] == nil { order.append(ref.threadId) }
            byThread[ref.threadId, default: []].append(ref)
        }

        var threads: [MailThread] = []
        for threadID in order.prefix(cappedThreads) {
            let group = (byThread[threadID] ?? []).prefix(Self.maxMessagesPerThread)
            var messages: [MailMessage] = []
            for ref in group {
                let detail = try await get(
                    path: "/gmail/v1/users/me/messages/\(ref.id)",
                    query: [URLQueryItem(name: "format", value: "full")]
                )
                // A message whose body will not parse is dropped rather than failing the thread; the
                // bounding and untrusted-text handling happen inside `MailMessage`.
                if let message = Self.parseFullMessage(detail) { messages.append(message) }
            }
            guard !messages.isEmpty else { continue }
            // Oldest first within a thread — a conversation reads forwards. ISO-8601 UTC strings sort
            // chronologically as text; a missing timestamp sorts first, which keeps it deterministic.
            messages.sort { ($0.receivedAt ?? "") < ($1.receivedAt ?? "") }
            threads.append(MailThread(id: threadID, messages: messages))
        }
        return threads
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
        let (refs, scope) = try await unreadMessageRefs(limit: limit)
        return (refs.map(\.id), scope)
    }

    /// The same selection as ``unreadMessageIDs(limit:)``, carrying the thread id each message
    /// belongs to. The count and list paths need only the ids; the thread path needs the grouping,
    /// and both come from one query so they can never describe different mailboxes.
    private func unreadMessageRefs(limit: Int) async throws -> (refs: [MessageRef], scope: MailUnreadScope) {
        let primary = try await listUnreadRefs(limit: limit, primaryOnly: true)
        if !primary.isEmpty {
            return (primary, .primary)
        }
        if await accountCategorizes() {
            return ([], .primary)
        }
        // No categories on this account: the filtered query can never match, so the plain inbox is
        // the only honest answer. Reported as `.inbox` so the surface stops claiming "Primary".
        return (try await listUnreadRefs(limit: limit, primaryOnly: false), .inbox)
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

    private func listUnreadRefs(limit: Int, primaryOnly: Bool) async throws -> [MessageRef] {
        var query = [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "labelIds", value: "UNREAD")
        ]
        if primaryOnly {
            query.append(URLQueryItem(name: "labelIds", value: Self.primaryCategoryLabel))
        }
        query.append(URLQueryItem(name: "maxResults", value: String(limit)))
        let data = try await get(path: "/gmail/v1/users/me/messages", query: query)
        guard let refs = Self.parseMessageRefs(data) else {
            throw MailError.providerFailed("Gmail's message list was not in the shape we read.")
        }
        return refs
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

    /// One entry of a `messages.list` response: a message id and the thread it belongs to.
    struct MessageRef: Equatable {
        let id: String
        let threadId: String
    }

    /// Message refs from a list response, or **nil when the response is not one**.
    ///
    /// The distinction carries the whole honesty of the count, which is the length of this array: a
    /// body that does not parse must not come back as an empty list, because empty means "your inbox
    /// is clear" and would be a calm, confident lie. A genuinely empty result is a real JSON object
    /// with no `messages` key (Gmail omits it), and only that reads as zero.
    ///
    /// A message that somehow arrived without a `threadId` is treated as its own thread — a message
    /// is a conversation of one — so the id is never dropped over a missing group key, and the count
    /// stays exact.
    static func parseMessageRefs(_ data: Data) -> [MessageRef]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let messages = root["messages"] as? [[String: Any]] {
            return messages.compactMap { message in
                guard let id = message["id"] as? String else { return nil }
                return MessageRef(id: id, threadId: message["threadId"] as? String ?? id)
            }
        }
        // No `messages` key. That is what Gmail returns for a genuinely empty result — but only
        // alongside `resultSizeEstimate`, which every list response carries. Requiring it is the
        // same guard the label read used (`id == "INBOX"`): it is what stops an error object, or a
        // shape change, from being counted as an inbox with nothing in it.
        return root["resultSizeEstimate"] != nil ? [] : nil
    }

    /// Message ids from a list response, or nil when the response is not one — the count and list
    /// paths' view of ``parseMessageRefs(_:)``, dropping the thread grouping they do not need.
    static func parseMessageIDs(_ data: Data) -> [String]? {
        parseMessageRefs(data)?.map(\.id)
    }

    /// The fields shared by the metadata and full parsers, or nil when the response has no id.
    ///
    /// Header names are matched **case-insensitively**: the RFC makes them case-insensitive and
    /// Gmail echoes whatever the sender wrote.
    private struct MessageFields {
        let id: String
        let from: String
        let subject: String
        let receivedAt: String?
        let rfc822MessageID: String?
        let preview: String?
    }

    private static func messageFields(_ root: [String: Any]) -> MessageFields? {
        guard let id = root["id"] as? String else { return nil }
        let headers = (root["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
        func header(_ name: String) -> String? {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
        }
        return MessageFields(
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
            // not part of `payload`, so the header allowlist does not govern it.
            //
            // Note that Google's reference describes `metadata` as returning "only email message
            // ID, labels, and email headers" and does not list `snippet` among them. Read
            // defensively for that reason: absent is a normal outcome here, never an error, and a
            // brief composed without previews is a thinner brief rather than a broken one. The
            // live probe in GmailAPIProviderTests is what settles which way this account behaves.
            preview: root["snippet"] as? String
        )
    }

    /// One message from a `format=metadata` response — headers and snippet, never a body.
    static func parseMessage(_ data: Data) -> MailMessage? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fields = messageFields(root)
        else { return nil }
        return MailMessage(
            id: fields.id, from: fields.from, subject: fields.subject,
            receivedAt: fields.receivedAt, rfc822MessageID: fields.rfc822MessageID,
            preview: fields.preview
        )
    }

    /// One message from a `format=full` response — the same fields plus the decoded, stripped and
    /// bounded body (NIC-258). The body is untrusted text and is bounded inside ``MailMessage``.
    static func parseFullMessage(_ data: Data) -> MailMessage? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fields = messageFields(root)
        else { return nil }
        let body = (root["payload"] as? [String: Any]).flatMap(Self.extractBodyText(from:))
        return MailMessage(
            id: fields.id, from: fields.from, subject: fields.subject,
            receivedAt: fields.receivedAt, rfc822MessageID: fields.rfc822MessageID,
            preview: fields.preview, body: body
        )
    }

    // MARK: - Reading a body out of a MIME tree

    /// The best plain-text rendering of a message payload, or nil when there is no readable text.
    ///
    /// A Gmail payload is a MIME tree: a single part with `body.data`, or a `parts` array that may
    /// nest (a `multipart/alternative` of text and HTML, inside a `multipart/mixed` with
    /// attachments). Plain text is preferred; HTML is the fallback, stripped to text. Attachments —
    /// a part with a filename or an `attachmentId` — are never read: a report summarises the
    /// message, not what was stapled to it, and an attachment's bytes are not text anyway.
    static func extractBodyText(from payload: [String: Any]) -> String? {
        var plain: String?
        var html: String?
        collectText(payload, plain: &plain, html: &html)
        if let plain, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plain
        }
        if let html { return stripHTML(html) }
        return nil
    }

    /// Walks the MIME tree, keeping the FIRST plain and first HTML text part it finds.
    ///
    /// First-wins, not concatenated: the opening part of a message is the message, and appending
    /// every later text part would drag quoted trails and signatures into a summary that wanted the
    /// new content. A branch with children is descended into and never read directly — only leaves
    /// carry `body.data`.
    private static func collectText(_ node: [String: Any], plain: inout String?, html: inout String?) {
        if let parts = node["parts"] as? [[String: Any]] {
            for part in parts { collectText(part, plain: &plain, html: &html) }
            return
        }
        let body = node["body"] as? [String: Any]
        let filename = node["filename"] as? String
        // An attachment part, even a text/* one: its bytes belong to a file, not to the message.
        if (filename?.isEmpty == false) || body?["attachmentId"] != nil { return }
        guard
            let encoded = body?["data"] as? String,
            let decoded = decodeBase64URL(encoded)
        else { return }
        switch (node["mimeType"] as? String)?.lowercased() {
        case "text/plain": if plain == nil { plain = decoded }
        case "text/html": if html == nil { html = decoded }
        default: break
        }
    }

    /// Gmail's web-safe base64 (`-`/`_`, unpadded, and often line-wrapped) into a UTF-8 string.
    static func decodeBase64URL(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        // Standard base64 wants the length padded to a multiple of four.
        while normalized.count % 4 != 0 { normalized.append("=") }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// HTML to readable plain text: scripts and styles removed, block boundaries turned into
    /// whitespace, tags dropped, and the handful of entities that survive that turned back into
    /// characters. Deliberately small — a bounded summary needs the words, not a faithful render —
    /// and it is where the whitespace collapse in ``MailMessage`` earns its keep, since crude tag
    /// removal leaves a lot of it behind.
    static func stripHTML(_ html: String) -> String {
        var text = removeElement("script", from: html)
        text = removeElement("style", from: text)

        var out = ""
        out.reserveCapacity(text.count)
        var insideTag = false
        var tagName = ""
        for character in text {
            if character == "<" {
                insideTag = true
                tagName = ""
                continue
            }
            if character == ">" {
                insideTag = false
                // Block-level closers and line breaks become a space so words do not fuse; the
                // whitespace collapse downstream folds the runs this leaves.
                let name = tagName.lowercased()
                if ["br", "/p", "/div", "/tr", "/li", "/h1", "/h2", "/h3", "p", "div", "tr", "li"].contains(name) {
                    out.append(" ")
                }
                continue
            }
            if insideTag {
                if tagName.count < 8, character != " " { tagName.append(character) }
                continue
            }
            out.append(character)
        }
        return decodeEntities(out)
    }

    /// Removes an element and its content wholesale (`<script>…</script>`), case-insensitively.
    private static func removeElement(_ tag: String, from html: String) -> String {
        var result = html
        while let open = result.range(of: "<\(tag)", options: .caseInsensitive),
              let close = result.range(
                  of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<result.endIndex
              ) {
            result.replaceSubrange(open.lowerBound..<close.upperBound, with: " ")
        }
        return result
    }

    /// The named and numeric entities common enough to matter in a summary. Anything else is left as
    /// written — a stray `&copy;` reads fine and is not worth a full entity table.
    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "\u{2014}", "&ndash;": "\u{2013}"
        ]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return result
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
