// Gmail integration: the API provider's parsing and error mapping.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore

/// The pure halves of the Gmail read adapter. The recurring theme is that **a count is the easiest
/// thing in this app to get quietly wrong** — a shape change or an error that parses as zero would
/// tell the user their inbox is clear when nobody actually looked.

// MARK: - The unread count

@Test("message ids are read from a list response; a genuinely empty result is zero")
func gmailParsesMessageIDs() throws {
    let body = Data(#"""
    {"messages":[{"id":"a","threadId":"t1"},{"id":"b","threadId":"t2"}],"resultSizeEstimate":2}
    """#.utf8)
    #expect(GmailAPIProvider.parseMessageIDs(body) == ["a", "b"])

    // Gmail omits `messages` entirely when nothing matches — a real, countable zero.
    #expect(GmailAPIProvider.parseMessageIDs(Data(#"{"resultSizeEstimate":0}"#.utf8)) == [])
}

@Test("a response that isn't a list reads as nothing at all, never as an empty inbox")
func gmailUnreadableListIsNotZero() {
    // The count IS the length of this array, so a body that does not parse must not come back
    // empty: "0 unread" is the most reassuring thing this app can say, and the easiest to get
    // quietly wrong. `nil` makes the caller fail honestly instead.
    #expect(GmailAPIProvider.parseMessageIDs(Data("not json".utf8)) == nil)
    #expect(GmailAPIProvider.parseMessageIDs(Data(#"[1,2,3]"#.utf8)) == nil)
    // An error object that reached the parser (a 200 carrying one) must not read as clear either:
    // it is a JSON object, so only the missing `resultSizeEstimate` distinguishes it from a real
    // empty result.
    #expect(GmailAPIProvider.parseMessageIDs(Data(#"{"error":{"code":403}}"#.utf8)) == nil)
}

// MARK: - Messages

@Test("a message is read from its headers, case-insensitively")
func gmailParsesAMessage() throws {
    // RFC 5322 makes header names case-insensitive, and Gmail echoes whatever the sender wrote.
    let body = Data(#"""
    {"id":"18f","payload":{"headers":[
      {"name":"from","value":"Mum <mum@example.com>"},
      {"name":"SUBJECT","value":"Sunday"},
      {"name":"Date","value":"Tue, 04 Aug 2026 13:20:00 -0400"}]}}
    """#.utf8)
    let message = try #require(GmailAPIProvider.parseMessage(body))

    #expect(message.id == "18f")
    #expect(message.from == "Mum <mum@example.com>")
    #expect(message.subject == "Sunday")
    #expect(message.receivedAt?.hasPrefix("2026-08-04") == true)
}

@Test("a message missing its headers is named, not dropped")
func gmailNamesTheGapsInAMessage() throws {
    let message = try #require(GmailAPIProvider.parseMessage(Data(#"{"id":"18f"}"#.utf8)))
    // A message with no subject is still a message; saying so beats hiding the row.
    #expect(message.from == "Unknown sender")
    #expect(message.subject == "(no subject)")
    #expect(message.receivedAt == nil)

    // Without an id there is nothing to address, so it is not a message.
    #expect(GmailAPIProvider.parseMessage(Data(#"{"payload":{}}"#.utf8)) == nil)
}

@Test("an unparseable date is absent rather than guessed")
func gmailParsesRFC2822Dates() {
    #expect(GmailAPIProvider.parseRFC2822("Tue, 04 Aug 2026 13:20:00 -0400") != nil)
    // Some senders omit the day name; the RFC allows it.
    #expect(GmailAPIProvider.parseRFC2822("4 Aug 2026 13:20:00 +0000") != nil)
    #expect(GmailAPIProvider.parseRFC2822("yesterday afternoon") == nil)
    #expect(GmailAPIProvider.parseRFC2822("") == nil)
}

@Test("the time shown is when Gmail received it, not what the sender's clock claimed")
func gmailPrefersInternalDate() throws {
    // Two visible bugs, one cause. The list is ordered by internalDate, so rendering header times
    // produced rows whose timestamps ran BACKWARDS (1:35 above 1:43); and a sender writing a
    // trailing zone name parsed to nothing, so that row silently lost its time altogether.
    let body = Data(#"""
    {"id":"m1","internalDate":"1786000000000","payload":{"headers":[
      {"name":"From","value":"Instacart <news@instacart.com>"},
      {"name":"Subject","value":"Save more by linking your Shoppers Club account"},
      {"name":"Date","value":"Mon, 4 Aug 2026 12:31:07 +0000 (UTC)"}
    ]}}
    """#.utf8)
    let message = try #require(GmailAPIProvider.parseMessage(body))

    // The `Date` header here is the exact form that used to yield nil — the row still gets a time.
    #expect(message.receivedAt != nil)
    #expect(GmailAPIProvider.parseRFC2822("Mon, 4 Aug 2026 12:31:07 +0000 (UTC)") == nil)
    #expect(message.receivedAt == GmailAPIProvider.parseInternalDate("1786000000000"))
}

@Test("a message without internalDate still falls back to a readable Date header")
func gmailFallsBackToTheDateHeader() throws {
    let body = Data(#"""
    {"id":"m2","payload":{"headers":[
      {"name":"Subject","value":"Sunday lunch?"},
      {"name":"Date","value":"Tue, 04 Aug 2026 13:20:00 -0400"}
    ]}}
    """#.utf8)
    #expect(try #require(GmailAPIProvider.parseMessage(body)).receivedAt != nil)
}

@Test("a label total says whether the account categorizes; an error object says nothing")
func gmailParsesLabelTotal() {
    #expect(GmailAPIProvider.parseLabelTotal(Data(#"{"id":"CATEGORY_PERSONAL","messagesTotal":4213}"#.utf8)) == 4213)
    // Gmail omits the counts for an empty label — a real zero, meaning "never categorized".
    #expect(GmailAPIProvider.parseLabelTotal(Data(#"{"id":"CATEGORY_PERSONAL"}"#.utf8)) == 0)
    // An error object, or another label, must not read as "this account does not categorize" —
    // that would silently switch the report back to showing everything.
    #expect(GmailAPIProvider.parseLabelTotal(Data(#"{"error":{"code":500}}"#.utf8)) == nil)
    #expect(GmailAPIProvider.parseLabelTotal(Data(#"{"id":"INBOX","messagesTotal":9}"#.utf8)) == nil)
}

// MARK: - Errors

@Test("401 is reconnect; 403 is configuration — sending both to Reconnect would loop the user")
func gmailSeparatesLapsedGrantsFromMisconfiguration() {
    // A rejected token: the grant lapsed (the Testing-status 7-day expiry, or a password change).
    #expect(GmailAPIProvider.mailError(forStatus: 401) == .reconnectRequired)

    // 403 is usually the Gmail API not enabled on the project, or a scope the grant lacks.
    // Reconnecting fixes neither, and telling the user to would send them round the same loop the
    // token-exchange bug did.
    guard case let .providerFailed(detail) = GmailAPIProvider.mailError(forStatus: 403) else {
        Issue.record("403 is a configuration fault, not a lapsed grant")
        return
    }
    #expect(detail.contains("Gmail API"))

    #expect(GmailAPIProvider.mailError(forStatus: 200) == nil)
    #expect(GmailAPIProvider.mailError(forStatus: 429) != nil)
}

@Test("an unconnected account is 'connect', never an error and never a zero")
func gmailMapsAuthErrors() {
    #expect(GmailAPIProvider.mailError(for: .notConnected) == .notConnected)
    // No Client ID is the same user-facing state: the integration was never set up.
    #expect(GmailAPIProvider.mailError(for: .clientIDMissing) == .notConnected)
    guard case .providerFailed = GmailAPIProvider.mailError(for: .providerFailed("boom")) else {
        Issue.record("a provider fault stays a provider fault")
        return
    }
}

// MARK: - Previews

@Test("Gmail's snippet becomes the message preview")
func gmailParsesSnippet() throws {
    // `snippet` is a TOP-LEVEL field of the Message resource, beside `id` and `internalDate`,
    // rather than part of `payload` — so the header allowlist does not govern it.
    let body = Data(#"""
    {"id":"m1","internalDate":"1755000000000","snippet":"Invoice 4021 is attached and due Friday.",
     "payload":{"headers":[{"name":"From","value":"Billing <billing@example.com>"},
                           {"name":"Subject","value":"Invoice 4021"}]}}
    """#.utf8)

    let message = try #require(GmailAPIProvider.parseMessage(body))
    #expect(message.preview == "Invoice 4021 is attached and due Friday.")
}

@Test("a message with no snippet has no preview, and is still a message")
func gmailToleratesAbsentSnippet() throws {
    // Google's reference describes `metadata` as returning "only email message ID, labels, and
    // email headers" and does not list `snippet`. Whether a given account returns one anyway is
    // what the live probe below settles; until then, absent must be an ordinary outcome — a brief
    // without previews is thinner, not broken.
    let body = Data(#"""
    {"id":"m2","payload":{"headers":[{"name":"Subject","value":"No preview here"}]}}
    """#.utf8)

    let message = try #require(GmailAPIProvider.parseMessage(body))
    #expect(message.preview == nil)
    #expect(message.subject == "No preview here")
}

@Test("a preview is collapsed and capped by the initializer, not by whoever remembers to")
func previewIsBounded() throws {
    // Bounded at construction rather than at the surface that renders or sends it: a limit applied
    // late is a limit one new caller forgets. Asserted through the initializer for that reason —
    // it is where the guarantee actually lives.
    func preview(_ raw: String?) -> String? {
        MailMessage(
            id: "m", from: "a@b.c", subject: "s", receivedAt: nil, rfc822MessageID: nil, preview: raw
        ).preview
    }

    // Snippets arrive carrying the original message's newlines. A preview spanning six lines costs
    // a model more attention than the fact inside it is worth, so whitespace collapses first.
    #expect(preview("  Meeting\n\nmoved  to\tThursday ") == "Meeting moved to Thursday")

    // Absent, not empty: "there was no preview" and "the message opens with nothing" are different
    // facts, and a composer told the second would describe an empty email.
    #expect(preview("   ") == nil)
    #expect(preview(nil) == nil)

    let bounded = try #require(preview(String(repeating: "a", count: MailMessage.previewLimit + 200)))
    #expect(bounded.count == MailMessage.previewLimit)
    // Ellipsised, so a reader can see it was cut rather than that the sender stopped mid-sentence.
    #expect(bounded.hasSuffix("\u{2026}"))
}

// MARK: - Live probe

// OPT-IN (CEREBRAL_GMAIL_TESTS=1): this one test reaches the real Gmail API with the account's own
// stored grant. Gated for the same reason every other live test here is — it needs a network, a
// connected account, and the Keychain — and kept to a single question.
//
//     CEREBRAL_GMAIL_TESTS=1 swift test --filter gmailSnippetProbe
//
// THE QUESTION: does `format=metadata` return `snippet`? Google's reference says metadata returns
// "only email message ID, labels, and email headers" and does not list it. If the probe says yes,
// previews cost nothing — no extra request, no format change, no re-consent. If it says no, the
// brief needs `format=full` plus MIME-part walking and HTML stripping, which is a much larger
// piece of work and would be scoped as its own increment.
//
// The probe reports the ANSWER rather than asserting one, because either answer is a fact about
// Google's API rather than a defect in this code — and a failing test is the wrong way to learn it.
@Test("PROBE: whether Gmail returns a snippet under format=metadata")
func gmailSnippetProbe() async throws {
    guard ProcessInfo.processInfo.environment["CEREBRAL_GMAIL_TESTS"] == "1" else { return }

    let session = GoogleAuthSession(
        secretStore: KeychainSecretCapability(), refresher: GoogleTokenExchange()
    )
    let provider = GmailAPIProvider(session: session)

    let messages: [MailMessage]
    do {
        messages = try await provider.unread(limit: 5)
    } catch {
        Issue.record("PROBE INCONCLUSIVE — could not read the inbox: \(error). Connect Gmail in Settings first.")
        return
    }
    guard !messages.isEmpty else {
        Issue.record("PROBE INCONCLUSIVE — no unread mail to sample. Leave one message unread and re-run.")
        return
    }

    let withPreview = messages.filter { $0.preview?.isEmpty == false }
    print("""

    ── snippet probe ──────────────────────────────────────────────
    format=metadata returned \(withPreview.count)/\(messages.count) messages carrying a snippet.
    \(withPreview.isEmpty
        ? "ANSWER: NO. Previews need format=full and MIME walking — scope that separately."
        : "ANSWER: YES. Previews are free at format=metadata, no extra request.")
    Longest preview: \(withPreview.map { $0.preview?.count ?? 0 }.max() ?? 0) characters \
    (capped at \(MailMessage.previewLimit)).
    ───────────────────────────────────────────────────────────────

    """)
}

// MARK: - Thread refs (format=metadata list)

@Test("message refs carry the thread id; a missing one falls back to the message's own id")
func gmailParsesMessageRefs() throws {
    let body = Data(#"""
    {"messages":[{"id":"a","threadId":"t1"},{"id":"b","threadId":"t1"},{"id":"c"}],"resultSizeEstimate":3}
    """#.utf8)
    #expect(GmailAPIProvider.parseMessageRefs(body) == [
        .init(id: "a", threadId: "t1"),
        .init(id: "b", threadId: "t1"),
        // No threadId: a message is a conversation of one, so it groups under itself rather than
        // being dropped — which would understate the count the list is the source of.
        .init(id: "c", threadId: "c")
    ])
    // The empty/error semantics are exactly parseMessageIDs': a real empty result is zero, anything
    // unparseable is nil, so a shape change never reads as a clear inbox.
    #expect(GmailAPIProvider.parseMessageRefs(Data(#"{"resultSizeEstimate":0}"#.utf8)) == [])
    #expect(GmailAPIProvider.parseMessageRefs(Data("not json".utf8)) == nil)
    #expect(GmailAPIProvider.parseMessageRefs(Data(#"{"error":{"code":403}}"#.utf8)) == nil)
    // The id-only view stays byte-for-byte what it always was.
    #expect(GmailAPIProvider.parseMessageIDs(body) == ["a", "b", "c"])
}

// MARK: - Body decoding (format=full)

@Test("Gmail's web-safe base64 decodes, padding and line wraps and all")
func gmailDecodesBase64URL() {
    // "Hello, Nick" → URL-safe base64. Unpadded, with an injected newline of the kind Gmail wraps at.
    #expect(GmailAPIProvider.decodeBase64URL("SGVsbG8sIE5pY2s=") == "Hello, Nick")
    #expect(GmailAPIProvider.decodeBase64URL("SGVsbG8sIE5pY2s") == "Hello, Nick") // no padding
    #expect(GmailAPIProvider.decodeBase64URL("SGVsbG8s\nIE5pY2s") == "Hello, Nick") // wrapped
    // The web-safe alphabet uses - and _ where standard base64 uses + and /. "??>" standard-encodes
    // to "Pz8+" and "???" to "Pz8/", so the web-safe forms exercise both substitutions.
    #expect(GmailAPIProvider.decodeBase64URL("Pz8-") == "??>")
    #expect(GmailAPIProvider.decodeBase64URL("Pz8_") == "???")
    #expect(GmailAPIProvider.decodeBase64URL("!!not base64!!") == nil)
}

@Test("HTML strips to readable text: scripts and styles gone, blocks spaced, entities decoded")
func gmailStripsHTML() {
    let html = """
    <html><head><style>.x{color:red}</style></head><body>
    <p>Hi&nbsp;Nick</p><script>alert('x')</script><div>Invoice&nbsp;#42 &amp; done</div>
    </body></html>
    """
    let text = GmailAPIProvider.stripHTML(html)
    #expect(!text.contains("color:red"))   // style content removed
    #expect(!text.contains("alert"))        // script content removed
    #expect(!text.contains("<"))            // tags gone
    #expect(text.contains("Hi Nick"))       // &nbsp; decoded, no fused words
    #expect(text.contains("Invoice #42 & done"))
}

@Test("plain text is preferred over HTML across a nested multipart tree")
func gmailPrefersPlainText() throws {
    let payload: [String: Any] = [
        "mimeType": "multipart/mixed",
        "parts": [
            [
                "mimeType": "multipart/alternative",
                "parts": [
                    ["mimeType": "text/html", "body": ["data": "PHA-SFRNTCB2ZXJzaW9uPC9wPg=="]],
                    // "The plain version" in web-safe base64.
                    ["mimeType": "text/plain", "body": ["data": "VGhlIHBsYWluIHZlcnNpb24="]]
                ]
            ]
        ]
    ]
    #expect(GmailAPIProvider.extractBodyText(from: payload) == "The plain version")
}

@Test("HTML is the fallback when there is no plain part")
func gmailFallsBackToHTML() throws {
    let payload: [String: Any] = [
        "mimeType": "text/html",
        // "<b>Only HTML</b>" in web-safe base64.
        "body": ["data": "PGI-T25seSBIVE1MPC9iPg=="]
    ]
    let body = try #require(GmailAPIProvider.extractBodyText(from: payload))
    #expect(body.contains("Only HTML"))
    #expect(!body.contains("<b>"))
}

@Test("an attachment part is never read as body text")
func gmailSkipsAttachments() {
    let payload: [String: Any] = [
        "mimeType": "multipart/mixed",
        "parts": [
            // A text/plain part that is actually an attachment (has a filename): not the message.
            ["mimeType": "text/plain", "filename": "notes.txt", "body": ["attachmentId": "abc"]],
            ["mimeType": "text/plain", "body": ["data": "VGhlIHJlYWwgYm9keQ=="]] // "The real body"
        ]
    ]
    #expect(GmailAPIProvider.extractBodyText(from: payload) == "The real body")
}

@Test("a full message carries the decoded, bounded body alongside its headers")
func gmailParsesFullMessage() throws {
    let body = Data(#"""
    {
      "id": "m1",
      "internalDate": "1793620800000",
      "snippet": "A short preview",
      "payload": {
        "headers": [
          {"name": "From", "value": "Dana <dana@x.com>"},
          {"name": "Subject", "value": "Lunch?"}
        ],
        "mimeType": "text/plain",
        "body": {"data": "QXJlIHlvdSBmcmVlIFRodXJzZGF5Pw=="}
      }
    }
    """#.utf8)
    let message = try #require(GmailAPIProvider.parseFullMessage(body))
    #expect(message.subject == "Lunch?")
    #expect(message.byline == "Dana")
    #expect(message.preview == "A short preview")
    #expect(message.body == "Are you free Thursday?")
}

// MARK: - Live body probe

// OPT-IN (CEREBRAL_GMAIL_TESTS=1): reads real unread threads with bodies through the stored grant.
//
//     CEREBRAL_GMAIL_TESTS=1 swift test --filter gmailBodyProbe
//
// Reports rather than asserts: body shapes vary wildly by sender, and the useful signal is that the
// decoder produced readable text of a sane length, not a fixed value.
@Test("PROBE: unread threads decode to bounded body text")
func gmailBodyProbe() async throws {
    guard ProcessInfo.processInfo.environment["CEREBRAL_GMAIL_TESTS"] == "1" else { return }

    let session = GoogleAuthSession(
        secretStore: KeychainSecretCapability(), refresher: GoogleTokenExchange()
    )
    let provider = GmailAPIProvider(session: session)

    let threads: [MailThread]
    do {
        threads = try await provider.unreadThreads(limit: 5)
    } catch {
        Issue.record("PROBE INCONCLUSIVE — could not read threads: \(error). Connect Gmail in Settings first.")
        return
    }
    guard !threads.isEmpty else {
        Issue.record("PROBE INCONCLUSIVE — no unread mail. Leave one message unread and re-run.")
        return
    }

    let bodies = threads.flatMap(\.messages).compactMap(\.body)
    print("""

    ── body probe ─────────────────────────────────────────────────
    \(threads.count) thread(s), \(threads.flatMap(\.messages).count) unread message(s).
    \(bodies.count) carried a decoded body (cap \(MailMessage.bodyLimit) chars).
    Longest: \(bodies.map(\.count).max() ?? 0) chars. Subjects: \(threads.map(\.subject).joined(separator: " | "))
    ───────────────────────────────────────────────────────────────

    """)
}

#endif
