// NIC-126: EventKit store-changed → live Today-panel refresh, coalesced against sync bursts.
#if canImport(EventKit)
import Foundation
import Testing
import EventKit

import CerebralMacAdapters

private final class RefreshCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Test("an EKEventStoreChanged burst triggers a single debounced refresh")
func calendarChangeObserverRefreshesOnStoreChange() async {
    let counter = RefreshCounter()
    let observer = CalendarChangeObserver(debounceMs: 100, onChange: { counter.increment() })

    // Three change notifications in quick succession (as a sync trickle produces) must coalesce.
    NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
    NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
    NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)

    for _ in 0..<50 {
        if counter.count >= 1 { break }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    // Give any un-coalesced extra work a chance to (wrongly) fire before asserting exactly one.
    try? await Task.sleep(nanoseconds: 150_000_000)
    #expect(counter.count == 1)
    withExtendedLifetime(observer) {}
}
#endif
