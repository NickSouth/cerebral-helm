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
#endif
