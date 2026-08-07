import Foundation
import Testing

import CerebralCore
import CerebralStorage

/// The Canvas scrape store (NIC-132): the latest scrape of the School dashboard's courses/grades
/// and upcoming deadlines persists in SQLite as one inspectable JSON blob, saving replaces
/// wholesale, and `clear()` purges it back to "no scrape yet". Losing/garbling the row degrades to
/// nil rather than throwing, so the widgets fall back to their honest unavailable state.

private func makeStore() throws -> (SQLiteCanvasSnapshotStore, SQLiteDatabase) {
    let db = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(db)
    return (SQLiteCanvasSnapshotStore(database: db), db)
}

private let sampleSnapshot = CanvasScrapeSnapshot(
    scrapedAt: Date(timeIntervalSince1970: 1_750_000_000),
    sourceURL: "https://umamherst.instructure.com/",
    courses: [
        CanvasCourse(
            id: "37331",
            name: "Theory of Computation",
            code: "COMPSCI 250",
            percent: 92.4,
            letterGrade: "A-",
            url: "https://umamherst.instructure.com/courses/37331"
        ),
        // A course with no score yet — percent/letter omitted, never fabricated.
        CanvasCourse(id: "40222", name: "College Writing", code: "ENGLWRIT 112"),
    ],
    deadlines: [
        CanvasDeadline(
            id: "a1",
            title: "Problem Set 7",
            dueAt: "2026-09-14T23:59:00",
            courseName: "COMPSCI 250",
            url: "https://umamherst.instructure.com/courses/37331/assignments/1"
        )
    ]
)

@Test("a store with no scrape loads nil — no scrape yet, never an error")
func canvasMissingSnapshotLoadsNil() throws {
    #expect(try makeStore().0.load() == nil)
}

@Test("a scrape snapshot round-trips: courses, deadlines, scrapedAt, source")
func canvasSnapshotRoundTrips() throws {
    let (store, _) = try makeStore()
    try store.save(sampleSnapshot)
    #expect(try store.load() == sampleSnapshot)
}

@Test("the newest scrape replaces the previous wholesale, never merges")
func canvasSaveReplacesWholesale() throws {
    let (store, _) = try makeStore()
    try store.save(sampleSnapshot)
    let newer = CanvasScrapeSnapshot(
        scrapedAt: Date(timeIntervalSince1970: 1_750_003_600),
        sourceURL: nil,
        courses: [CanvasCourse(id: "99", name: "Seminar")],
        deadlines: []
    )
    try store.save(newer)
    #expect(try store.load() == newer)
}

@Test("clear() purges the snapshot back to no-scrape (disconnect)")
func canvasClearPurges() throws {
    let (store, _) = try makeStore()
    try store.save(sampleSnapshot)
    try store.clear()
    #expect(try store.load() == nil)
}

@Test("an unreadable snapshot row degrades to nil rather than throwing")
func canvasUndecodableRowLoadsNil() throws {
    let (store, db) = try makeStore()
    _ = try db.run(
        "INSERT INTO canvas_snapshot (id, snapshot_json, updated_at) VALUES (1, ?, ?);",
        [.text("{not valid json"), .text("2026-07-28T00:00:00.000Z")]
    )
    #expect(try store.load() == nil)
}
