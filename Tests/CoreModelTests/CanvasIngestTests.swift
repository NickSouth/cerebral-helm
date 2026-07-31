import Foundation
import Testing

import CerebralCore

/// NIC-132 Increment 4a: decoding + validating the Chrome extension's ingest payload into a stored
/// snapshot. The body is untrusted — an unsupported version or malformed body is rejected, degenerate
/// rows are dropped rather than failing the whole scrape, blank optionals normalise to nil, and row
/// counts are capped.

private let scrapedAtISO = "2023-11-14T22:13:20Z" // == Date(timeIntervalSince1970: 1_700_000_000)
private let scrapedAtDate = Date(timeIntervalSince1970: 1_700_000_000)

private func payload(
    version: Int = CanvasIngest.schemaVersion,
    scrapedAt: String = scrapedAtISO,
    sourceUrl: String? = "https://umamherst.instructure.com/",
    courses: [CanvasIngestPayload.Course] = [],
    deadlines: [CanvasIngestPayload.Deadline] = []
) -> CanvasIngestPayload {
    CanvasIngestPayload(
        schemaVersion: version, scrapedAt: scrapedAt, sourceUrl: sourceUrl,
        courses: courses, deadlines: deadlines
    )
}

@Test("a valid payload validates into a snapshot with parsed scrapedAt, courses, and deadlines")
func canvasIngestValidPayload() throws {
    let snapshot = try CanvasIngest.snapshot(from: payload(
        courses: [
            CanvasIngestPayload.Course(id: "37331", name: "Theory of Computation", code: "COMPSCI 250", percent: 92.4, letterGrade: "A-"),
        ],
        deadlines: [
            CanvasIngestPayload.Deadline(id: "a1", title: "Problem Set 7", dueAt: "2026-09-14T23:59:00", courseName: "COMPSCI 250"),
        ]
    ))
    #expect(snapshot.scrapedAt == scrapedAtDate)
    #expect(snapshot.sourceURL == "https://umamherst.instructure.com/")
    #expect(snapshot.courses == [CanvasCourse(id: "37331", name: "Theory of Computation", code: "COMPSCI 250", percent: 92.4, letterGrade: "A-")])
    #expect(snapshot.deadlines.first?.title == "Problem Set 7")
    #expect(snapshot.deadlines.first?.dueAt == "2026-09-14T23:59:00")
}

@Test("an unsupported schema version is rejected, never guessed")
func canvasIngestUnsupportedVersion() {
    #expect(throws: CanvasIngestError.unsupportedVersion(999)) {
        try CanvasIngest.snapshot(from: payload(version: 999))
    }
}

@Test("a body that isn't valid ingest JSON is rejected as malformed")
func canvasIngestMalformedBody() {
    #expect(throws: CanvasIngestError.self) {
        try CanvasIngest.snapshot(fromBody: Data("{not valid json".utf8))
    }
}

@Test("an invalid scrapedAt is rejected as malformed")
func canvasIngestBadScrapedAt() {
    #expect(throws: CanvasIngestError.self) {
        try CanvasIngest.snapshot(from: payload(scrapedAt: "not-a-date"))
    }
}

@Test("degenerate rows (missing id / blank name / blank title) are dropped, not fatal")
func canvasIngestDropsDegenerateRows() throws {
    let snapshot = try CanvasIngest.snapshot(from: payload(
        courses: [
            CanvasIngestPayload.Course(id: "1", name: "Real Course"),
            CanvasIngestPayload.Course(id: "", name: "No Id"),
            CanvasIngestPayload.Course(id: "2", name: "   "),
        ],
        deadlines: [
            CanvasIngestPayload.Deadline(id: "d1", title: "Real Assignment"),
            CanvasIngestPayload.Deadline(id: "", title: "No Id"),
            CanvasIngestPayload.Deadline(id: "d2", title: ""),
        ]
    ))
    #expect(snapshot.courses.map(\.id) == ["1"])
    #expect(snapshot.deadlines.map(\.id) == ["d1"])
}

@Test("blank optional strings normalise to nil, never a fabricated value")
func canvasIngestBlankOptionalsAreNil() throws {
    let snapshot = try CanvasIngest.snapshot(from: payload(
        sourceUrl: "   ",
        courses: [CanvasIngestPayload.Course(id: "1", name: "Course", code: "  ", letterGrade: "", url: "  ")],
        deadlines: [CanvasIngestPayload.Deadline(id: "d1", title: "A", dueAt: "  ", courseName: "", url: " ")]
    ))
    #expect(snapshot.sourceURL == nil)
    let course = snapshot.courses.first
    #expect(course?.code == nil)
    #expect(course?.letterGrade == nil)
    #expect(course?.url == nil)
    let deadline = snapshot.deadlines.first
    #expect(deadline?.dueAt == nil)
    #expect(deadline?.courseName == nil)
    #expect(deadline?.url == nil)
}

@Test("an omitted gradeHidden defaults to false")
func canvasIngestGradeHiddenDefaultsFalse() throws {
    let snapshot = try CanvasIngest.snapshot(from: payload(
        courses: [CanvasIngestPayload.Course(id: "1", name: "Course", percent: 80)]
    ))
    #expect(snapshot.courses.first?.gradeHidden == false)
}

@Test("row counts are capped so an oversized scrape can't balloon local state")
func canvasIngestCapsRowCounts() throws {
    let courses = (0..<(CanvasIngest.maxCourses + 5)).map {
        CanvasIngestPayload.Course(id: "c\($0)", name: "Course \($0)")
    }
    let deadlines = (0..<(CanvasIngest.maxDeadlines + 5)).map {
        CanvasIngestPayload.Deadline(id: "d\($0)", title: "Assignment \($0)")
    }
    let snapshot = try CanvasIngest.snapshot(from: payload(courses: courses, deadlines: deadlines))
    #expect(snapshot.courses.count == CanvasIngest.maxCourses)
    #expect(snapshot.deadlines.count == CanvasIngest.maxDeadlines)
}

@Test("a fractional-seconds scrapedAt is accepted")
func canvasIngestFractionalSecondsScrapedAt() throws {
    let snapshot = try CanvasIngest.snapshot(from: payload(scrapedAt: "2023-11-14T22:13:20.500Z"))
    // Second precision on read is enough for the freshness cue.
    #expect(Int(snapshot.scrapedAt.timeIntervalSince1970) == 1_700_000_000)
}

@Test("a valid payload decodes end-to-end from a raw JSON body")
func canvasIngestDecodesFromBody() throws {
    let json = """
    {
      "schemaVersion": 1,
      "scrapedAt": "\(scrapedAtISO)",
      "sourceUrl": "https://umamherst.instructure.com/",
      "courses": [{ "id": "37331", "name": "Theory of Computation", "code": "COMPSCI 250", "percent": 92.4, "letterGrade": "A-" }],
      "deadlines": [{ "id": "a1", "title": "Problem Set 7", "dueAt": "2026-09-14T23:59:00" }]
    }
    """
    let snapshot = try CanvasIngest.snapshot(fromBody: Data(json.utf8))
    #expect(snapshot.courses.first?.name == "Theory of Computation")
    #expect(snapshot.deadlines.first?.id == "a1")
    #expect(snapshot.scrapedAt == scrapedAtDate)
}
