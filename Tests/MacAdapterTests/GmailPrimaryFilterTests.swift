// Which mail the Gmail adapter actually asks for.
//
// The count and the listing must describe the SAME slice of the mailbox — five rows under a count
// of forty is the defect this whole shape exists to prevent — and that slice is Primary wherever
// the account categorizes, because promotions are most of an inbox and almost none of its meaning.
//
// Driven through a stubbed transport rather than pure helpers, because the behavior under test IS
// the requests: which labels are asked for, and what happens when the filtered one comes back empty.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore
import CerebralTools

// MARK: - Harness

/// Serves canned bodies by request, recording every URL the adapter asked for.
private final class StubTransport: URLProtocol, @unchecked Sendable {
    /// `(url) -> (status, body)`. Set per test; read from the protocol's class methods.
    nonisolated(unsafe) static var respond: (@Sendable (URL) -> (Int, Data))?
    nonisolated(unsafe) static var requested: [URL] = []
    private static let lock = NSLock()

    static func record(_ url: URL) {
        lock.lock(); requested.append(url); lock.unlock()
    }

    static func reset(_ handler: @escaping @Sendable (URL) -> (Int, Data)) {
        lock.lock(); requested = []; lock.unlock()
        respond = handler
    }

    static var recorded: [URL] { lock.lock(); defer { lock.unlock() }; return requested }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.respond else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.record(url)
        let (status, body) = handler(url)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class StubSecrets: SecretStoreManaging, @unchecked Sendable {
    private let values: [String: String]
    init(_ values: [String: String]) { self.values = values }
    func store(reference: String, value: String) async throws {}
    func delete(reference: String) async throws {}
    func readValue(reference: String) async throws -> String {
        guard let value = values[reference] else { throw NativeCapabilityError.notFound(reference) }
        return value
    }
}

private struct UnusedRefresher: GoogleTokenRefreshing {
    func refresh(
        refreshToken: String, clientID: String, clientSecret: String?, now: Date
    ) async throws -> GoogleTokens {
        throw GoogleAuthError.providerFailed("must not refresh")
    }
}

/// A provider whose token is live (so nothing refreshes) and whose transport is the stub.
private func stubbedProvider() throws -> GmailAPIProvider {
    let tokens = GoogleTokens(
        accessToken: "live", refreshToken: "r",
        expiresAt: Date().addingTimeInterval(3600), scope: nil, address: "nick@gmail.com"
    )
    let session = GoogleAuthSession(
        secretStore: StubSecrets([GoogleTokenBlob.reference: try GoogleTokenBlob.encode(tokens)]),
        refresher: UnusedRefresher()
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubTransport.self]
    return GmailAPIProvider(session: session, urlSession: URLSession(configuration: configuration))
}

/// A list response holding `count` ids.
private func listBody(_ count: Int) -> Data {
    let ids = (0..<count).map { #"{"id":"m\#($0)","threadId":"t\#($0)"}"# }.joined(separator: ",")
    return Data(#"{"messages":[\#(ids)],"resultSizeEstimate":\#(count)}"#.utf8)
}

private let emptyList = Data(#"{"resultSizeEstimate":0}"#.utf8)

/// A label resource. `messagesTotal` is what says whether this account categorizes at all.
private func labelBody(total: Int) -> Data {
    Data(#"{"id":"CATEGORY_PERSONAL","name":"CATEGORY_PERSONAL","messagesTotal":\#(total)}"#.utf8)
}

private func isPrimaryQuery(_ url: URL) -> Bool {
    url.query?.contains("labelIds=CATEGORY_PERSONAL") == true
}

// MARK: - The Primary filter

/// Serialized: every test in here drives the one shared stubbed transport, so running them
/// concurrently would have each answering another's requests.
@Suite("Gmail Primary filter", .serialized)
struct GmailPrimaryFilterSuite {


    @Test("the count asks for unread Primary mail only — promotions are excluded at the source")
    func countAsksForPrimaryOnly() async throws {
        StubTransport.reset { _ in (200, listBody(12)) }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == 12)
        #expect(summary.scope == .primary)
        #expect(summary.isCapped == false)

        let asked = try #require(StubTransport.recorded.first)
        let query = try #require(asked.query)
        // INBOX + UNREAD + CATEGORY_PERSONAL, which Gmail ANDs — exactly "unread in Primary".
        #expect(query.contains("labelIds=INBOX"))
        #expect(query.contains("labelIds=UNREAD"))
        #expect(query.contains("labelIds=CATEGORY_PERSONAL"))
        // One request, and it reads no message: ids only.
        #expect(StubTransport.recorded.count == 1)
    }

    @Test("the listing asks for the same slice the count did")
    func listingMatchesTheCountsFilter() async throws {
        StubTransport.reset { url in
            // The list call, then one metadata fetch per id.
            url.path.hasSuffix("/messages") ? (200, listBody(2)) : (200, messageBody())
        }
        _ = try await stubbedProvider().unread(limit: 5)

        let listCall = try #require(StubTransport.recorded.first)
        #expect(isPrimaryQuery(listCall))
    }

    @Test("a count past the ceiling is reported as a floor, not as an exact total")
    func countIsCappedHonestly() async throws {
        StubTransport.reset { _ in (200, listBody(GmailAPIProvider.countCeiling)) }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == GmailAPIProvider.countCeiling)
        // The surface renders this as "100+"; claiming exactly 100 would invent a precision Gmail
        // was never asked for.
        #expect(summary.isCapped)
    }

    // MARK: - Accounts that do not categorize

    @Test("an empty Primary on a categorizing account is zero — NOT the whole inbox")
    func emptyPrimaryOnACategorizingAccountIsZero() async throws {
        // The owner's real case (verified 2026-08-04): personal mail kept up with, promotions piled
        // high. Falling back here answered "nothing unread that matters" with a hundred promotional
        // messages — defeating the filter at the exact moment it was working.
        StubTransport.reset { url in
            if url.path.contains("/labels/") { return (200, labelBody(total: 4213)) }
            return isPrimaryQuery(url) ? (200, emptyList) : (200, listBody(137))
        }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == 0)
        #expect(summary.scope == .primary)
        // The unfiltered inbox was never even asked for.
        #expect(StubTransport.recorded.contains { !isPrimaryQuery($0) && $0.path.hasSuffix("/messages") } == false)
    }

    @Test("an account that does not categorize still falls back, so mail never disappears")
    func nonCategorizingAccountFallsBackToTheWholeInbox() async throws {
        // Categories off: CATEGORY_PERSONAL has never been applied to anything, so the filtered
        // query is empty FOREVER. Reporting "nothing unread" there would be a calm, confident lie
        // about an inbox with hundreds in it.
        StubTransport.reset { url in
            if url.path.contains("/labels/") { return (200, labelBody(total: 0)) }
            return isPrimaryQuery(url) ? (200, emptyList) : (200, listBody(37))
        }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == 37)
        #expect(summary.scope == .inbox) // said plainly, so the label stops claiming "Primary"
    }

    @Test("a failed categorization check keeps the filter on rather than opening the floodgates")
    func categorizationCheckFailsSafe() async throws {
        // A transient error must not dump the promotions back on screen; the filter stays applied.
        StubTransport.reset { url in
            if url.path.contains("/labels/") { return (500, Data("boom".utf8)) }
            return isPrimaryQuery(url) ? (200, emptyList) : (200, listBody(137))
        }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == 0)
        #expect(summary.scope == .primary)
    }

    @Test("a genuinely clear inbox is zero, and says so as Primary")
    func trulyEmptyInboxIsZero() async throws {
        StubTransport.reset { url in
            url.path.contains("/labels/") ? (200, labelBody(total: 4213)) : (200, emptyList)
        }
        let summary = try await stubbedProvider().unreadSummary()

        #expect(summary.count == 0)
        #expect(summary.scope == .primary)
        #expect(summary.isCapped == false)
    }

    @Test("the listing falls back the same way the count does, so the two never disagree")
    func listingFallsBackTogetherWithTheCount() async throws {
        StubTransport.reset { url in
            if url.path.contains("/labels/") { return (200, labelBody(total: 0)) }
            if url.path.hasSuffix("/messages") {
                return isPrimaryQuery(url) ? (200, emptyList) : (200, listBody(1))
            }
            return (200, messageBody())
        }
        let messages = try await stubbedProvider().unread(limit: 5)

        // If only the count fell back, the report would show a number with no rows under it.
        #expect(messages.count == 1)
    }

    // MARK: - Failure stays honest

    @Test("an unreadable list fails rather than counting as an empty inbox")
    func unreadableListFailsHonestly() async throws {
        StubTransport.reset { _ in (200, Data(#"{"unexpected":true}"#.utf8)) }

        await #expect(throws: MailError.self) { _ = try await stubbedProvider().unreadSummary() }
    }

}

private func messageBody() -> Data {
    Data(#"""
    {"id":"m0","payload":{"headers":[
      {"name":"From","value":"Mum <mum@example.com>"},
      {"name":"Subject","value":"Sunday lunch?"},
      {"name":"Message-ID","value":"<abc@example.com>"}
    ]}}
    """#.utf8)
}
#endif
