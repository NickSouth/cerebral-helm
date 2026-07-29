// NIC-132 Increment 5: the Canvas widget producer reads the local scrape store and emits the two
// School widgets' live data (courses + deadlines) as widget.data.changed events, refreshing on
// demand (the ingest endpoint calls it) and resuming immediately after a visibility pause.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

private struct Boom: Error {}

private final class StubCanvasStore: CanvasSnapshotStore, @unchecked Sendable {
    enum Mode { case snapshot(CanvasScrapeSnapshot?); case failure }
    private let mode: Mode
    init(_ mode: Mode) { self.mode = mode }
    func load() throws -> CanvasScrapeSnapshot? {
        switch mode {
        case let .snapshot(snapshot): return snapshot
        case .failure: throw Boom()
        }
    }
    func save(_ snapshot: CanvasScrapeSnapshot) throws {}
    func clear() throws {}
}

private final class Emissions: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ json: String) { lock.withLock { items.append(json) } }
    var all: [String] { lock.withLock { items } }
}

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

/// Extracts `(widgetId, state)` from an emitted `widget.data.changed` event JSON.
private func widgetState(_ json: String) -> (widgetId: String, state: String)? {
    guard
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
        let payload = object["payload"] as? [String: Any],
        let widgetId = payload["widgetId"] as? String,
        let widget = payload["widget"] as? [String: Any],
        let state = widget["state"] as? String
    else { return nil }
    return (widgetId, state)
}

private func statesByWidget(_ emissions: Emissions) -> [String: String] {
    var result: [String: String] = [:]
    for json in emissions.all {
        if let parsed = widgetState(json) { result[parsed.widgetId] = parsed.state }
    }
    return result
}

private func makePublisher(_ store: any CanvasSnapshotStore, _ emissions: Emissions) -> CanvasWidgetPublisher {
    CanvasWidgetPublisher(store: store, now: { fixedNow }, emit: { emissions.add($0) })
}

@Test("a refresh emits both the courses and deadlines widgets from a stored scrape")
func canvasPublisherRefreshEmitsBothWidgets() async {
    let snapshot = CanvasScrapeSnapshot(
        scrapedAt: fixedNow,
        courses: [CanvasCourse(id: "1", name: "Theory of Computation", code: "COMPSCI 250", percent: 92)],
        deadlines: [CanvasDeadline(id: "a1", title: "Problem Set 7", dueAt: "2026-09-14T23:59:00")]
    )
    let emissions = Emissions()
    await makePublisher(StubCanvasStore(.snapshot(snapshot)), emissions).refresh()

    let states = statesByWidget(emissions)
    #expect(states["courses"] == "ready")
    #expect(states["deadlines"] == "ready")
}

@Test("a never-scraped store emits both widgets as unavailable")
func canvasPublisherNilStoreEmitsUnavailable() async {
    let emissions = Emissions()
    await makePublisher(StubCanvasStore(.snapshot(nil)), emissions).refresh()

    let states = statesByWidget(emissions)
    #expect(states["courses"] == "unavailable")
    #expect(states["deadlines"] == "unavailable")
}

@Test("a store read failure emits both widgets as unavailable, never fabricated")
func canvasPublisherFailingStoreEmitsUnavailable() async {
    let emissions = Emissions()
    await makePublisher(StubCanvasStore(.failure), emissions).refresh()

    let states = statesByWidget(emissions)
    #expect(states["courses"] == "unavailable")
    #expect(states["deadlines"] == "unavailable")
}

@Test("resuming from a visibility pause emits a fresh sample immediately")
func canvasPublisherResumeEmitsImmediately() async {
    let snapshot = CanvasScrapeSnapshot(
        scrapedAt: fixedNow,
        courses: [CanvasCourse(id: "1", name: "Course")],
        deadlines: []
    )
    let emissions = Emissions()
    let publisher = makePublisher(StubCanvasStore(.snapshot(snapshot)), emissions)
    await publisher.setActive(false) // was active → no emit
    #expect(emissions.all.isEmpty)
    await publisher.setActive(true) // resume → emits both widgets at once
    #expect(emissions.all.count == 2)
}
#endif
