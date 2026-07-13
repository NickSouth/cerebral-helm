// Mid-session app-install detection (NIC-150): watch the Applications folders so
// a freshly installed app is re-discovered and its reference live-reloaded
// without waiting for the user to open the More Apps picker.
#if canImport(AppKit)
import Foundation

/// Watches the user-writable Applications folders and fires a callback on change.
/// A seam so the observer's debounce/coalesce logic is unit-testable with a
/// scripted trigger — no real filesystem events.
public protocol ApplicationsFolderWatching: Sendable {
    /// Begin watching. `onChange` fires once per raw filesystem change to a
    /// watched directory (an install writes many, hence the observer debounces).
    func start(onChange: @escaping @Sendable () -> Void)
    /// Stop watching and release every underlying resource. Idempotent.
    func stop()
}

/// Re-discovers installed applications shortly after the Applications folders
/// change, so a mid-session install becomes openable by id this session — no
/// relaunch (NIC-150). It owns only the debounce/coalesce policy; the actual
/// re-mint + catalog reload is the injected `reload` closure (the shell wires it
/// to `CommandRuntime.updateReferences`), and the raw watching is the `watcher`
/// seam.
///
/// A software install writes many files in a burst; each raw change reschedules
/// a single trailing reload, so one install triggers exactly one reload once the
/// folder settles.
public final class ApplicationsFolderObserver: @unchecked Sendable {
    private let watcher: any ApplicationsFolderWatching
    private let reload: @Sendable () -> Void
    private let debounce: DispatchTimeInterval
    /// Serialises all debounce state — `generation` is only ever touched here, so
    /// no lock is needed.
    private let queue = DispatchQueue(label: "local.cerebralhelm.apps-folder-observer")
    /// Bumped on every raw change and on stop; a scheduled reload fires only if it
    /// is still the latest generation when its debounce elapses (coalescing).
    private var generation = 0
    private var started = false

    /// `debounce` is the quiet period after the last change before the reload runs
    /// — long enough to collapse an install's write burst, short enough to feel
    /// immediate.
    public init(
        watcher: any ApplicationsFolderWatching = LiveApplicationsFolderWatcher(),
        debounce: DispatchTimeInterval = .milliseconds(1500),
        reload: @escaping @Sendable () -> Void
    ) {
        self.watcher = watcher
        self.debounce = debounce
        self.reload = reload
    }

    deinit {
        watcher.stop()
    }

    /// Begin observing. Idempotent — a second call is a no-op.
    public func start() {
        var alreadyStarted = false
        queue.sync {
            alreadyStarted = started
            started = true
        }
        guard !alreadyStarted else { return }
        watcher.start { [weak self] in self?.onRawChange() }
    }

    /// Stop observing and cancel any pending reload.
    public func stop() {
        watcher.stop()
        queue.sync {
            generation &+= 1 // invalidate any in-flight debounce
            started = false
        }
    }

    private func onRawChange() {
        queue.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            let scheduled = self.generation
            self.queue.asyncAfter(deadline: .now() + self.debounce) { [weak self] in
                guard let self else { return }
                // A newer change arrived during the quiet period — let its own
                // trailing reload run instead. One install → one reload.
                guard scheduled == self.generation else { return }
                self.reload()
            }
        }
    }
}

/// The live watcher: a `DispatchSource` file-system-object source per directory,
/// keyed on `.write` (kqueue `NOTE_WRITE`, which fires when a directory's entries
/// change — an app added, removed, or renamed). `/System/Applications` is
/// deliberately not watched: it is SIP-static and never changes at runtime.
/// A directory that does not exist (a user with no `~/Applications`) is simply
/// skipped.
public final class LiveApplicationsFolderWatcher: ApplicationsFolderWatching, @unchecked Sendable {
    private let directories: [URL]
    private let queue = DispatchQueue(label: "local.cerebralhelm.apps-folder-watcher", qos: .utility)
    private let lock = NSLock()
    private var sources: [DispatchSourceFileSystemObject] = []

    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    public init(directories: [URL] = LiveApplicationsFolderWatcher.defaultDirectories) {
        self.directories = directories
    }

    deinit {
        stop()
    }

    public func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard sources.isEmpty else { return }
        for directory in directories {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: .write, queue: queue
            )
            source.setEventHandler { onChange() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        for source in sources {
            source.cancel() // the cancel handler closes the descriptor
        }
        sources.removeAll()
    }
}
#endif
