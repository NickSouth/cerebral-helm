// Per-display window occupancy — the trigger behind the dashboard's recede (NIC-152).
#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// One on-screen window, reduced to what occupancy actually cares about.
///
/// Deliberately not the navigator's `AXWindowRecord`: that carries titles and minimized state but
/// **no frame**, and a frame is the entire question here. Titles would also cost the Screen
/// Recording permission, which this must not need — the recede is ambient behaviour that has to
/// work on a fresh machine with nothing granted.
public struct OccupancyWindow: Equatable, Sendable {
    public let windowID: UInt32
    public let pid: pid_t
    /// AppKit screen coordinates (y-up), already converted from CoreGraphics' y-down space, so this
    /// can be compared directly against the display frames the topology reports.
    public let frame: CGRect

    public init(windowID: UInt32, pid: pid_t, frame: CGRect) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
    }
}

/// A display as occupancy sees it: the stable id the rest of the shell keys everything by, and the
/// frame to test windows against.
public struct OccupancyDisplay: Equatable, Sendable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// The window-list seam, so the occupancy rule is unit-testable with scripted windows — no real
/// desktop, no permissions, no timing.
public protocol OnScreenWindowReading: Sendable {
    func onScreenWindows() -> [OccupancyWindow]
}

/// Watches which displays are covered by real work, and reports each display's state after it has
/// held still long enough to be worth acting on (NIC-152).
///
/// **Why this is per-display and not application focus.** Focus is one global boolean, and the
/// requirement is two displays in different states at the same instant: the laptop screen fully
/// present because nothing is on it, the external display receded because the user's work is there.
/// The backdrop is also borderless, sub-normal-level and non-activating by policy, so it is built
/// never to take focus — its own focus events say almost nothing about what the user is doing.
///
/// **What counts as occupancy** is a product rule, not a technical one, and it is enforced in two
/// independent ways so neither alone is load-bearing:
///
/// - Only windows at CoreGraphics layer 0 — ordinary application windows. This drops the Dock, the
///   menu bar, desktop icons, and every CerebralHelm surface that floats above normal windows
///   (More Apps, the navigator, the mode menu, the sidebar), as well as the backdrop itself, which
///   sits *below* normal.
/// - CerebralHelm's own windows are excluded unless the host names them. Today the host names
///   exactly one: **Settings** — a place you go to work, where a busy dashboard behind it is noise.
///   The confirmation panel is normal-level and would otherwise qualify, but it is a momentary
///   interruption *about* the dashboard; dimming behind it would just flash.
///
/// The sidebar is the case that proves the rule: it is a real native window on that display, so a
/// naive "any window" test would dim the whole surface every time the left-edge hover-reveal fired.
///
/// **Hysteresis is required, not optional**, and it is asymmetric. A window that opens and closes
/// quickly would otherwise strobe the dashboard through a 620ms fade. Receding waits for the
/// display to stay covered; returning is quicker, because being wrong about "the user came back"
/// is far more annoying than being slow about "the user left".
///
/// Main-thread confined: `start`/`stop`/`refresh` and the callback all run on main, matching the
/// webview work the host performs in response.
public final class DisplayOccupancyObserver {
    /// How often the desktop is re-read. There is no notification for "a window moved to the other
    /// monitor", so this is a poll — but a cheap one (a single `CGWindowListCopyWindowInfo`), and
    /// the debounce below means a faster tick would not make the result arrive sooner.
    public static let pollInterval: TimeInterval = 0.5
    /// How long a display must stay covered before it recedes.
    public static let recedeDelay: TimeInterval = 0.9
    /// How long a display must stay clear before it returns. Shorter on purpose — see above.
    public static let returnDelay: TimeInterval = 0.3

    /// The share of a display a window must cover to count.
    ///
    /// Any-intersection would be wrong: a window straddling two monitors by a few pixels would
    /// recede the display it is barely touching. A fraction rather than a fixed size so the same
    /// rule reads the same on a laptop panel and a 6K display.
    public static let minimumCoverage: CGFloat = 0.02

    private let source: any OnScreenWindowReading
    private let displays: () -> [OccupancyDisplay]
    private let ownPID: pid_t
    /// The host's answer to "which of *our* windows count right now" — re-asked every tick, because
    /// Settings opening and closing is exactly the transition this must notice.
    private let countedOwnWindows: () -> Set<UInt32>

    /// Fired on main whenever a display's settled state changes, with that display's id and whether
    /// it should now recede. Only real transitions are reported; a steady desktop is silent.
    public var onOccupancyChange: ((String, Bool) -> Void)?

    /// The last state actually reported per display.
    private var published: [String: Bool] = [:]
    /// A candidate state seen but not yet held long enough, with the time it was first seen.
    private var pending: [String: (value: Bool, since: Date)] = [:]
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    /// Injected so the debounce is testable without waiting in real time.
    private let now: () -> Date

    public init(
        source: any OnScreenWindowReading = LiveOnScreenWindows(),
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        displays: @escaping () -> [OccupancyDisplay],
        countedOwnWindows: @escaping () -> Set<UInt32> = { [] },
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.ownPID = ownPID
        self.displays = displays
        self.countedOwnWindows = countedOwnWindows
        self.now = now
    }

    deinit {
        timer?.invalidate()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Begin polling. Idempotent.
    public func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // `.common` so the polling survives a menu tracking or a live window drag — the two moments
        // the desktop is most likely to be changing.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // A display that just disappeared must stop being remembered, or reconnecting it would
            // restore a stale verdict from before it was unplugged.
            self?.forgetDisconnectedDisplays()
            self?.refresh()
        }

        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        pending.removeAll()
    }

    /// Re-read the desktop, advance the debounce, and report anything that has settled. Safe to
    /// call directly (tests, or the host after a change it already knows about).
    public func refresh() {
        let current = displays()
        let occupied = Self.occupiedDisplays(
            windows: source.onScreenWindows(),
            displays: current,
            ownPID: ownPID,
            countedOwnWindows: countedOwnWindows()
        )
        let at = now()

        for display in current {
            settle(display.id, raw: occupied.contains(display.id), at: at)
        }
    }

    /// The state the host should apply to a display right now, for a surface that has just appeared
    /// and missed every transition so far (a companion backdrop on a hot-plugged display, or a
    /// webview whose bridge only just finished its handshake).
    public func currentState(of displayID: String) -> Bool {
        published[displayID] ?? false
    }

    /// Advance one display's debounce. A raw value equal to what is already published cancels any
    /// pending change outright — the transition never happened as far as anyone else is concerned.
    private func settle(_ displayID: String, raw: Bool, at instant: Date) {
        // First sighting of this display: adopt its state immediately. Debouncing here would make a
        // screen that is already covered — the common case on a display the user is working on when
        // CerebralHelm launches — spend the delay looking fully present first.
        guard let currentValue = published[displayID] else {
            published[displayID] = raw
            pending[displayID] = nil
            onOccupancyChange?(displayID, raw)
            return
        }

        // Back to what is already published: whatever was building cancels outright. As far as
        // anything downstream is concerned the transition never happened, which is precisely what
        // stops a window that opens and closes quickly from strobing the dashboard.
        guard raw != currentValue else {
            pending[displayID] = nil
            return
        }

        guard let candidate = pending[displayID], candidate.value == raw else {
            pending[displayID] = (value: raw, since: instant)
            return
        }

        let required = raw ? Self.recedeDelay : Self.returnDelay
        guard instant.timeIntervalSince(candidate.since) >= required else { return }

        published[displayID] = raw
        pending[displayID] = nil
        onOccupancyChange?(displayID, raw)
    }

    private func forgetDisconnectedDisplays() {
        let live = Set(displays().map(\.id))
        published = published.filter { live.contains($0.key) }
        pending = pending.filter { live.contains($0.key) }
    }

    /// Which displays are covered by work, given a snapshot. Pure — the whole product rule lives
    /// here and nowhere else, so it can be argued with in a test rather than on a desktop.
    public static func occupiedDisplays(
        windows: [OccupancyWindow],
        displays: [OccupancyDisplay],
        ownPID: pid_t,
        countedOwnWindows: Set<UInt32>
    ) -> Set<String> {
        var occupied: Set<String> = []
        for window in windows {
            if window.pid == ownPID && !countedOwnWindows.contains(window.windowID) {
                continue
            }
            for display in displays where !occupied.contains(display.id) {
                let area = display.frame.width * display.frame.height
                guard area > 0 else { continue }
                let overlap = display.frame.intersection(window.frame)
                guard !overlap.isNull else { continue }
                if (overlap.width * overlap.height) / area >= minimumCoverage {
                    occupied.insert(display.id)
                }
            }
        }
        return occupied
    }
}

/// The live desktop read.
///
/// `CGWindowListCopyWindowInfo` is the right tool here and, importantly, needs **no permission** for
/// what this asks of it: bounds, owner and layer are always returned. Only `kCGWindowName` is gated
/// behind Screen Recording, and occupancy never looks at titles. Accessibility would have been the
/// obvious alternative — the navigator already uses it — but it needs a grant that ad-hoc signing
/// invalidates on every rebuild, and its window records carry no frame.
public struct LiveOnScreenWindows: OnScreenWindowReading {
    public init() {}

    public func onScreenWindows() -> [OccupancyWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // The origin of AppKit's coordinate space: CoreGraphics measures y down from the top of the
        // primary display, AppKit measures it up from the bottom of that same display. `screens[0]`
        // is the primary by definition, so its top edge is where the two systems meet.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0

        return raw.compactMap { entry -> OccupancyWindow? in
            // Layer 0 is an ordinary application window. Everything else is chrome (the Dock, the
            // menu bar) or floats above normal windows — including CerebralHelm's own summoned
            // surfaces, which must never make the dashboard behind them recede.
            guard (entry[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            // A fully transparent window covers nothing, whatever its frame says.
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }
            guard
                let windowID = entry[kCGWindowNumber as String] as? UInt32,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                cgFrame.width > 0, cgFrame.height > 0
            else { return nil }

            return OccupancyWindow(
                windowID: windowID,
                pid: pid,
                frame: Self.appKitFrame(cgFrame, primaryTop: primaryTop)
            )
        }
    }

    /// Flip a CoreGraphics global rect into AppKit screen coordinates. Split out and made internal
    /// so the one piece of coordinate arithmetic in this file can be tested rather than trusted.
    static func appKitFrame(_ cgFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(
            x: cgFrame.minX,
            y: primaryTop - cgFrame.maxY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }
}
#endif
