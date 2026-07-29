import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-132 Increment 3: mapping the latest Canvas scrape into the `courses` and `deadlines` widget
/// envelopes with staleness, and emitting them as `widget.data.changed` bridge events. A hidden
/// grade never leaks its score across the bridge; failure/never-scraped degrades to unavailable.

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
private let staleAfter: TimeInterval = 6 * 3600 // 6 hours

private func snapshot(
    scrapedAt: Date = fixedNow,
    courses: [CanvasCourse] = [],
    deadlines: [CanvasDeadline] = []
) -> CanvasScrapeSnapshot {
    CanvasScrapeSnapshot(scrapedAt: scrapedAt, sourceURL: "https://umamherst.instructure.com/", courses: courses, deadlines: deadlines)
}

// MARK: - Courses

@Test("a fresh scrape maps courses to a ready widget with grades, omitting missing ones")
func canvasCoursesReadyMapping() {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(courses: [
            CanvasCourse(id: "37331", name: "Theory of Computation", code: "COMPSCI 250", percent: 92.4, letterGrade: "A-"),
            CanvasCourse(id: "40222", name: "College Writing", code: "ENGLWRIT 112"),
        ])),
        now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.widgetId == "courses")
    #expect(widget.state == "ready")
    #expect(widget.headline == "2 courses")
    #expect(widget.freshness?.label == "just now")
    #expect(widget.freshness?.observedAt == fixedNow)
    #expect(widget.data?.items.count == 2)
    #expect(widget.data?.items.first?.percent == 92.4)
    #expect(widget.data?.items.first?.letterGrade == "A-")
    // A course with no score omits percent/letter, never fabricated.
    #expect(widget.data?.items.last?.percent == nil)
    #expect(widget.data?.items.last?.letterGrade == nil)
}

@Test("a single course reads as '1 course' (singular)")
func canvasCoursesSingularHeadline() {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(courses: [CanvasCourse(id: "1", name: "Seminar")])),
        now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.headline == "1 course")
}

@Test("a hidden grade is flagged hidden and its score never crosses the bridge")
func canvasCoursesHiddenGradeStripsScore() {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(courses: [
            CanvasCourse(id: "1", name: "Statistics", code: "STAT 240", percent: 80, letterGrade: "B-", gradeHidden: true)
        ])),
        now: fixedNow, staleAfter: staleAfter
    )
    let item = widget.data?.items.first
    #expect(item?.gradeHidden == true)
    #expect(item?.percent == nil) // the hidden score is not sent
    #expect(item?.letterGrade == nil)
}

@Test("a scrape with no courses maps to an honest empty widget")
func canvasCoursesEmptyMapping() {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(courses: [])), now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
    #expect(widget.freshness == nil)
}

@Test("a never-scraped store maps courses to unavailable (connect the extension)")
func canvasCoursesUnavailableWhenNeverScraped() {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(nil), now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
}

@Test("a store read failure maps courses to unavailable, never a fabricated widget")
func canvasCoursesUnavailableOnFailure() {
    struct Boom: Error {}
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .failure(Boom()), now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "unavailable")
    #expect(widget.data == nil)
}

@Test("a scrape older than staleAfter maps to a stale widget that still shows the courses + age")
func canvasCoursesStaleWhenOld() {
    let old = fixedNow.addingTimeInterval(-2 * 3600) // 2h ago
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(scrapedAt: old, courses: [CanvasCourse(id: "1", name: "Seminar")])),
        now: fixedNow, staleAfter: 3600 // stale after 1h
    )
    #expect(widget.state == "stale")
    #expect(widget.data?.items.count == 1)
    #expect(widget.freshness?.label == "2h ago")
}

// MARK: - Deadlines

@Test("deadlines map to a ready widget sorted soonest-first, undated last")
func canvasDeadlinesSortedMapping() {
    let widget = BridgeEventFactory.canvasDeadlinesWidget(
        from: .success(snapshot(deadlines: [
            CanvasDeadline(id: "c", title: "Undated Reading"),
            CanvasDeadline(id: "b", title: "Essay", dueAt: "2026-09-16T09:00:00"),
            CanvasDeadline(id: "a", title: "Problem Set", dueAt: "2026-09-14T23:59:00"),
        ])),
        now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "ready")
    #expect(widget.headline == "3 due soon")
    #expect(widget.data?.items.map(\.title) == ["Problem Set", "Essay", "Undated Reading"])
}

@Test("no upcoming work maps deadlines to an honest empty widget")
func canvasDeadlinesEmptyMapping() {
    let widget = BridgeEventFactory.canvasDeadlinesWidget(
        from: .success(snapshot(deadlines: [])), now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "empty")
    #expect(widget.data == nil)
    #expect(widget.emptyMessage?.isEmpty == false)
}

@Test("a never-scraped store maps deadlines to unavailable")
func canvasDeadlinesUnavailableWhenNeverScraped() {
    let widget = BridgeEventFactory.canvasDeadlinesWidget(
        from: .success(nil), now: fixedNow, staleAfter: staleAfter
    )
    #expect(widget.state == "unavailable")
}

// MARK: - Age label + event emission

@Test("the data-age label buckets seconds/minutes/hours/days")
func canvasAgeLabelBuckets() {
    func label(secondsAgo: TimeInterval) -> String? {
        BridgeEventFactory.canvasCoursesWidget(
            from: .success(snapshot(scrapedAt: fixedNow.addingTimeInterval(-secondsAgo),
                                    courses: [CanvasCourse(id: "1", name: "X")])),
            now: fixedNow, staleAfter: .greatestFiniteMagnitude
        ).freshness?.label
    }
    #expect(label(secondsAgo: 30) == "just now")
    #expect(label(secondsAgo: 90) == "1m ago")
    #expect(label(secondsAgo: 3 * 3600) == "3h ago")
    #expect(label(secondsAgo: 2 * 86400) == "2d ago")
}

@Test("the courses widget emits as a widget.data.changed event and round-trips")
func canvasCoursesEmitsWidgetDataChangedEvent() throws {
    let widget = BridgeEventFactory.canvasCoursesWidget(
        from: .success(snapshot(courses: [
            CanvasCourse(id: "1", name: "Statistics", code: "STAT 240", percent: 80, gradeHidden: true)
        ])),
        now: fixedNow, staleAfter: staleAfter
    )
    let event = BridgeEventFactory.widgetDataChangedEvent(
        widgetId: "courses", widget: widget, id: "brevt_test00000132", timestamp: fixedNow
    )
    #expect(event.type == .widgetDataChanged)

    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)
    #expect(json.contains("\"type\":\"widget.data.changed\""))
    #expect(json.contains("\"widgetId\":\"courses\""))
    #expect(json.contains("\"gradeHidden\":true"))
    // The hidden score must not appear anywhere in the emitted payload.
    #expect(!json.contains("\"percent\""))

    let decoded = try CerebralHelmBridgeEvent(data: Data(json.utf8))
    #expect(decoded.type == .widgetDataChanged)
    #expect(decoded.eventID == "brevt_test00000132")
}
