import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-131 Increment 3: mapping the active-repos reader's result into the `repositories`
/// widget envelope, and emitting it as a `widget.data.changed` bridge event.

private func repo(_ name: String, branch: String?) -> RepoStatus {
    RepoStatus(
        id: name, name: name, branch: branch,
        path: "/Users/example/Projects/\(name)",
        lastActivityAt: Date(timeIntervalSince1970: 1_000)
    )
}

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a non-empty read maps to a ready widget with one row per repo")
func readyMapping() {
    let widget = BridgeEventFactory.repositoriesWidget(
        from: .success([repo("cerebral-helm", branch: "main"), repo("notes", branch: nil)]),
        now: fixedNow
    )

    #expect(widget.widgetId == "repositories")
    #expect(widget.state == "ready")
    #expect(widget.headline == "2 repositories")
    #expect(widget.emptyMessage == nil)
    #expect(widget.freshness?.observedAt == fixedNow)
    #expect(widget.data?.items.count == 2)
    #expect(widget.data?.items.first?.branch == "main")
    // An unresolved branch is left nil, never fabricated.
    #expect(widget.data?.items.last?.branch == nil)
    #expect(widget.data?.items.last?.path == "/Users/example/Projects/notes")
}

@Test("a single repo reads as '1 repository' (singular)")
func singularHeadline() {
    let widget = BridgeEventFactory.repositoriesWidget(
        from: .success([repo("solo", branch: "dev")]), now: fixedNow
    )
    #expect(widget.headline == "1 repository")
}

@Test("a readable-but-empty root maps to an empty widget with an honest message")
func emptyMapping() {
    let widget = BridgeEventFactory.repositoriesWidget(from: .success([]), now: fixedNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a read failure maps to an unavailable widget, never a fabricated one")
func unavailableMapping() {
    let widget = BridgeEventFactory.repositoriesWidget(
        from: .failure(ActiveReposError.rootUnavailable("/nope")), now: fixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
}

@Test("the widget emits as a widget.data.changed event; nil branches are omitted, not null")
func emitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.repositoriesWidget(
        from: .success([repo("cerebral-helm", branch: "main"), repo("notes", branch: nil)]),
        now: fixedNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "repositories", widget: widget, id: "brevt_test00000131", timestamp: fixedNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"repositories\""))
    #expect(json.contains("\"branch\":\"main\""))
    // The synthesized encoding omits a nil branch rather than writing an explicit null.
    #expect(!json.contains("\"branch\":null"))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000131")
}
