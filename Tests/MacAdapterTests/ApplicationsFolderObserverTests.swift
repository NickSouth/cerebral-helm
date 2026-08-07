// NIC-150: the Applications-folder observer debounces raw filesystem changes into
// exactly one reference reload per install burst. The live DispatchSource path is
// exercised on a real host; here the watching is a seam so the coalesce logic is
// deterministic.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters

/// A scripted watcher: `trigger()` stands in for one raw filesystem change.
private final class FakeApplicationsFolderWatcher: ApplicationsFolderWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (@Sendable () -> Void)?

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock(); self.onChange = onChange; lock.unlock()
    }

    func stop() {
        lock.lock(); onChange = nil; lock.unlock()
    }

    func trigger() {
        lock.lock(); let handler = onChange; lock.unlock()
        handler?()
    }
}

/// Thread-safe reload tally (the reload runs on the observer's private queue).
private final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private let debounce = DispatchTimeInterval.milliseconds(40)
private let settle = Duration.milliseconds(300)

@Test("an install's change burst coalesces into a single reference reload")
func burstCoalescesToOneReload() async throws {
    let watcher = FakeApplicationsFolderWatcher()
    let counter = ReloadCounter()
    let observer = ApplicationsFolderObserver(
        watcher: watcher, debounce: debounce, reload: { counter.increment() }
    )
    observer.start()

    // A software install writes many entries in quick succession.
    for _ in 0..<8 { watcher.trigger() }

    try await Task.sleep(for: settle)
    #expect(counter.count == 1)
}

@Test("a later, separate change re-arms and reloads again")
func separateBurstsEachReload() async throws {
    let watcher = FakeApplicationsFolderWatcher()
    let counter = ReloadCounter()
    let observer = ApplicationsFolderObserver(
        watcher: watcher, debounce: debounce, reload: { counter.increment() }
    )
    observer.start()

    watcher.trigger()
    try await Task.sleep(for: settle)
    #expect(counter.count == 1)

    // A second install later is its own reload, not swallowed by the first.
    watcher.trigger()
    try await Task.sleep(for: settle)
    #expect(counter.count == 2)
}

@Test("stopping cancels a pending reload")
func stopCancelsPendingReload() async throws {
    let watcher = FakeApplicationsFolderWatcher()
    let counter = ReloadCounter()
    let observer = ApplicationsFolderObserver(
        watcher: watcher, debounce: debounce, reload: { counter.increment() }
    )
    observer.start()

    watcher.trigger()
    observer.stop() // before the debounce elapses

    try await Task.sleep(for: settle)
    #expect(counter.count == 0)
}
#endif
