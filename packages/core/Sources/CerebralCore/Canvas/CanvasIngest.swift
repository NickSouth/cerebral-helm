import Foundation

/// The wire payload the Canvas Chrome extension POSTs to the local ingest endpoint (NIC-132).
///
/// This is the versioned SEAM that isolates the fragile DOM scrape from the rest of the app: the
/// extension's only job is to produce this shape, and everything downstream depends only on it, so
/// re-tuning selectors never touches native code. `schemaVersion` lets the native side reject a
/// payload from an extension it can't read rather than guessing. Field shapes mirror the stored
/// domain (`CanvasCourse`/`CanvasDeadline`) so the mapping is a straight, validated copy.
public struct CanvasIngestPayload: Equatable, Sendable, Codable {
    public let schemaVersion: Int
    /// ISO-8601 instant the scrape was captured (the extension's clock).
    public let scrapedAt: String
    public let sourceUrl: String?
    public let courses: [Course]
    public let deadlines: [Deadline]

    public struct Course: Equatable, Sendable, Codable {
        public let id: String
        public let name: String
        public let code: String?
        public let percent: Double?
        public let letterGrade: String?
        public let gradeHidden: Bool?
        public let url: String?

        public init(
            id: String,
            name: String,
            code: String? = nil,
            percent: Double? = nil,
            letterGrade: String? = nil,
            gradeHidden: Bool? = nil,
            url: String? = nil
        ) {
            self.id = id
            self.name = name
            self.code = code
            self.percent = percent
            self.letterGrade = letterGrade
            self.gradeHidden = gradeHidden
            self.url = url
        }
    }

    public struct Deadline: Equatable, Sendable, Codable {
        public let id: String
        public let title: String
        public let dueAt: String?
        public let courseName: String?
        public let url: String?

        public init(
            id: String,
            title: String,
            dueAt: String? = nil,
            courseName: String? = nil,
            url: String? = nil
        ) {
            self.id = id
            self.title = title
            self.dueAt = dueAt
            self.courseName = courseName
            self.url = url
        }
    }

    public init(
        schemaVersion: Int,
        scrapedAt: String,
        sourceUrl: String? = nil,
        courses: [Course],
        deadlines: [Deadline]
    ) {
        self.schemaVersion = schemaVersion
        self.scrapedAt = scrapedAt
        self.sourceUrl = sourceUrl
        self.courses = courses
        self.deadlines = deadlines
    }
}

/// Why an ingest body was rejected (NIC-132). Coarse by design — the diagnostic is never surfaced
/// to a caller verbatim (the endpoint answers with a status code, not this text), so it can't leak
/// anything about the request beyond "we couldn't accept it".
public enum CanvasIngestError: Error, Equatable {
    /// The payload's `schemaVersion` isn't the one this build understands.
    case unsupportedVersion(Int)
    /// The body couldn't be decoded, or a required field was invalid.
    case malformed(String)
}

/// Decodes and validates an ingest body into a stored ``CanvasScrapeSnapshot`` (NIC-132).
///
/// This is the boundary between an external process (the Chrome extension) and local state, so the
/// body is never trusted: an unsupported schema version and a malformed body are rejected outright,
/// while individual degenerate rows (missing id/name/title) are dropped rather than failing the
/// whole scrape, and blank optional strings normalise to `nil` (never a fabricated value). Row
/// counts are capped so an oversized scrape can't balloon local state — the byte size of the request
/// is bounded separately at the transport (the listener, Increment 4b).
public enum CanvasIngest {
    /// The ingest schema version this build understands. A payload with any other version is
    /// rejected rather than guessed — the extension and app move in lockstep.
    public static let schemaVersion = 1

    /// The largest number of rows kept from one scrape (a defensive cap on local state size).
    public static let maxCourses = 100
    public static let maxDeadlines = 200

    /// Decode a raw ingest body and validate it into a snapshot.
    public static func snapshot(fromBody data: Data) throws -> CanvasScrapeSnapshot {
        let payload: CanvasIngestPayload
        do {
            payload = try JSONDecoder().decode(CanvasIngestPayload.self, from: data)
        } catch {
            throw CanvasIngestError.malformed("body is not valid ingest JSON")
        }
        return try snapshot(from: payload)
    }

    /// Validate an already-decoded payload into a snapshot.
    public static func snapshot(from payload: CanvasIngestPayload) throws -> CanvasScrapeSnapshot {
        guard payload.schemaVersion == schemaVersion else {
            throw CanvasIngestError.unsupportedVersion(payload.schemaVersion)
        }
        guard let scrapedAt = parseISO(payload.scrapedAt) else {
            throw CanvasIngestError.malformed("scrapedAt is not a valid ISO-8601 instant")
        }

        let courses = payload.courses
            .filter { !$0.id.isEmpty && !isBlank($0.name) }
            .prefix(maxCourses)
            .map {
                CanvasCourse(
                    id: $0.id,
                    name: $0.name,
                    code: nonBlank($0.code),
                    percent: $0.percent,
                    letterGrade: nonBlank($0.letterGrade),
                    gradeHidden: $0.gradeHidden ?? false,
                    url: nonBlank($0.url)
                )
            }

        let deadlines = payload.deadlines
            .filter { !$0.id.isEmpty && !isBlank($0.title) }
            .prefix(maxDeadlines)
            .map {
                CanvasDeadline(
                    id: $0.id,
                    title: $0.title,
                    dueAt: nonBlank($0.dueAt),
                    courseName: nonBlank($0.courseName),
                    url: nonBlank($0.url)
                )
            }

        return CanvasScrapeSnapshot(
            scrapedAt: scrapedAt,
            sourceURL: nonBlank(payload.sourceUrl),
            courses: Array(courses),
            deadlines: Array(deadlines)
        )
    }

    private static func isBlank(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func nonBlank(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Parses an ISO-8601 instant, accepting both plain and fractional-seconds forms.
    private static func parseISO(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
