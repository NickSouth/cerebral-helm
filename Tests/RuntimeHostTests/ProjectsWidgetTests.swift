import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-129 Increment 2: mapping the active-projects reader's result into the `projects`
/// widget envelope, and emitting it as a `widget.data.changed` bridge event.

private func project(_ name: String, hasDescriptor: Bool) -> ProjectSummary {
    ProjectSummary(
        id: name,
        name: name,
        path: "/Users/example/Projects/\(name)",
        descriptorPath: hasDescriptor ? "/Users/example/Projects/\(name)/PROJECT.md" : nil,
        hasDescriptor: hasDescriptor,
        importance: hasDescriptor ? 5 : nil,
        lastActivityAt: Date(timeIntervalSince1970: 1_000)
    )
}

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@Test("a non-empty read maps to a ready widget with one row per project")
func projectsReadyMapping() {
    let widget = BridgeEventFactory.projectsWidget(
        from: .success([project("CerebralHelm", hasDescriptor: true), project("Undocumented", hasDescriptor: false)]),
        now: fixedNow
    )

    #expect(widget.widgetId == "projects")
    #expect(widget.state == "ready")
    #expect(widget.headline == "2 projects")
    #expect(widget.emptyMessage == nil)
    #expect(widget.freshness?.observedAt == fixedNow)
    #expect(widget.data?.items.count == 2)
    #expect(widget.data?.items.first?.hasDescriptor == true)
    #expect(widget.data?.items.first?.descriptorPath == "/Users/example/Projects/CerebralHelm/PROJECT.md")
    // A project without a descriptor reports it honestly and omits the descriptor path.
    #expect(widget.data?.items.last?.hasDescriptor == false)
    #expect(widget.data?.items.last?.descriptorPath == nil)
}

@Test("a single project reads as '1 project' (singular)")
func projectsSingularHeadline() {
    let widget = BridgeEventFactory.projectsWidget(
        from: .success([project("solo", hasDescriptor: true)]), now: fixedNow
    )
    #expect(widget.headline == "1 project")
}

@Test("a readable-but-empty root maps to an empty projects widget with an honest message")
func projectsEmptyMapping() {
    let widget = BridgeEventFactory.projectsWidget(from: .success([]), now: fixedNow)
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a read failure maps to an unavailable projects widget, never a fabricated one")
func projectsUnavailableMapping() {
    let widget = BridgeEventFactory.projectsWidget(
        from: .failure(ActiveProjectsError.rootUnavailable("/nope")), now: fixedNow
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
}

@Test("the projects widget emits as a widget.data.changed event; nil descriptor paths are omitted, not null")
func projectsEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.projectsWidget(
        from: .success([project("CerebralHelm", hasDescriptor: true), project("Undocumented", hasDescriptor: false)]),
        now: fixedNow
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "projects", widget: widget, id: "brevt_test00000129", timestamp: fixedNow
    )

    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"projects\""))
    #expect(json.contains("\"hasDescriptor\":true"))
    #expect(json.contains("\"hasDescriptor\":false"))
    // The synthesized encoding omits a nil descriptorPath rather than writing an explicit null.
    #expect(!json.contains("\"descriptorPath\":null"))

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000129")
}
