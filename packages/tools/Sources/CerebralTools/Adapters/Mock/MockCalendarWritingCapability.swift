import CerebralCore

/// Deterministic mock ``CalendarWritingCapability`` for pre-Mac builds and tests. Records what it
/// was asked to write and returns a stable id, so a test can assert the exact event that would
/// have been created without touching a real calendar store.
public final class MockCalendarWritingCapability: CalendarWritingCapability, @unchecked Sendable {
    public struct Written: Equatable, Sendable {
        public let title: String
        public let startsAt: String
        public let endsAt: String
        public let calendarID: String?
        public let location: String?
        public let notes: String?

        public init(
            title: String, startsAt: String, endsAt: String,
            calendarID: String?, location: String?, notes: String?
        ) {
            self.title = title
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.calendarID = calendarID
            self.location = location
            self.notes = notes
        }
    }

    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var calendarTitle: String?
    public private(set) var written: [Written] = []

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        calendarTitle: String? = "Mock Calendar"
    ) {
        self.matrix = matrix
        self.fault = fault
        self.calendarTitle = calendarTitle
    }

    public func createEvent(
        title: String,
        startsAt: String,
        endsAt: String,
        calendarID: String?,
        location: String?,
        notes: String?
    ) async throws -> (eventID: String, calendarTitle: String?) {
        try CapabilityGate.check(CapabilityMatrix.Capability.calendarWrite, matrix: matrix, fault: fault)
        written.append(
            Written(
                title: title, startsAt: startsAt, endsAt: endsAt,
                calendarID: calendarID, location: location, notes: notes
            )
        )
        return ("mock-event-\(written.count)", calendarTitle)
    }
}
