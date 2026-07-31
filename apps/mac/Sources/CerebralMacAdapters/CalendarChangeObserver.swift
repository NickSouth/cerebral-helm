// Live calendar-change refresh for the Today panel (NIC-126).
#if canImport(EventKit)
@preconcurrency import EventKit
import Foundation

/// Observes EventKit's store-changed notification so a newly created, edited, or deleted calendar
/// event (including one synced in from Google/iCloud) refreshes the Today panel within about a
/// second, instead of waiting out the ``CalendarPublisher``'s slow poll cadence (NIC-126).
///
/// It holds a **long-lived** `EKEventStore` on purpose: EventKit only delivers
/// `.EKEventStoreChanged` to a live store instance, and the publisher's stores are ephemeral
/// (created per fetch). It requests no access itself — Calendar access is process-wide, granted by
/// the publisher at point of use — so constructing it never prompts. Notifications are coalesced
/// (a sync burst can post several) into a single refresh via a short debounce, so the publisher
/// samples once rather than repeatedly.
public final class CalendarChangeObserver: @unchecked Sendable {
    private let store = EKEventStore()
    private let onChange: @Sendable () -> Void
    private let debounce: DispatchTimeInterval
    private let queue = DispatchQueue(label: "com.cerebralhelm.calendar-change-observer")
    private var pending: DispatchWorkItem?
    private var token: NSObjectProtocol?

    /// - Parameters:
    ///   - debounceMs: how long to coalesce a burst of change notifications before refreshing.
    ///   - onChange: invoked (once per coalesced burst) when the calendar store changes.
    public init(debounceMs: Int = 1000, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        self.debounce = .milliseconds(debounceMs)
        // `object: nil` catches every store-changed notification (any writer — Calendar.app, a
        // provider sync); we only read, so our own fetches never post one.
        token = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.scheduleRefresh()
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func scheduleRefresh() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: work)
        }
    }
}
#endif
