// NIC-151 (Nick's window registry): the ChromeProfileLauncher focuses a profile's
// existing window instead of reopening one, by remembering the window it launched.
// The AppleScript primitives are faked so the reuse-vs-launch decision is pure.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralMacAdapters
import CerebralTools

/// A scriptable-Chrome stand-in. `windowIDs`/`front` are mutable so a test can
/// simulate a window appearing after a launch (via the launcher's `settle` hook).
final class FakeChromeScripting: ChromeWindowScripting, @unchecked Sendable {
    private let lock = NSLock()
    private var windowIDs: [Int]
    private var front: Int?
    private var tabsByWindow: [Int: [(index: Int, url: String)]] = [:]
    private(set) var focusCalls: [Int] = []
    private(set) var openedTabs: [(window: Int, url: URL)] = []
    private(set) var focusedTabs: [(window: Int, index: Int)] = []

    init(windowIDs: [Int] = [], front: Int? = nil) {
        self.windowIDs = windowIDs
        self.front = front
    }

    func setWindows(_ ids: [Int], front: Int?) {
        lock.lock(); defer { lock.unlock() }
        windowIDs = ids
        self.front = front
    }

    func setTabs(_ tabs: [(index: Int, url: String)], inWindow id: Int) {
        lock.lock(); defer { lock.unlock() }
        tabsByWindow[id] = tabs
    }

    func resetCalls() {
        lock.lock(); defer { lock.unlock() }
        focusCalls.removeAll()
        openedTabs.removeAll()
        focusedTabs.removeAll()
    }

    var recordedFocusCalls: [Int] { lock.lock(); defer { lock.unlock() }; return focusCalls }
    var recordedTabs: [(window: Int, url: URL)] { lock.lock(); defer { lock.unlock() }; return openedTabs }
    var recordedFocusedTabs: [(window: Int, index: Int)] { lock.lock(); defer { lock.unlock() }; return focusedTabs }

    func openWindowIDs() -> [Int] { lock.lock(); defer { lock.unlock() }; return windowIDs }
    func frontWindowID() -> Int? { lock.lock(); defer { lock.unlock() }; return front }
    func focusWindow(id: Int) -> Bool { lock.lock(); defer { lock.unlock() }; focusCalls.append(id); return true }
    func openTab(inWindowID id: Int, url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        openedTabs.append((id, url))
        return true
    }
    func tabs(inWindowID id: Int) -> [(index: Int, url: String)] {
        lock.lock(); defer { lock.unlock() }
        return tabsByWindow[id] ?? []
    }
    func focusTab(windowID id: Int, tabIndex: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        focusedTabs.append((id, tabIndex))
        return true
    }
}

/// A workspace where Chrome is installed and launches record their arguments.
final class LauncherWorkspace: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    let hasChrome: Bool
    private var launches: [[String]] = []
    private var documents: [URL] = []
    private var urls: [URL] = []

    init(hasChrome: Bool = true) { self.hasChrome = hasChrome }

    var recordedLaunches: [[String]] { lock.lock(); defer { lock.unlock() }; return launches }
    /// URLs handed to a named app as documents — the plain "open in Chrome" path, used when no
    /// profile could be resolved.
    var documentOpens: [URL] { lock.lock(); defer { lock.unlock() }; return documents }
    /// URLs handed to the default handler — the no-Chrome fallback.
    var urlOpens: [URL] { lock.lock(); defer { lock.unlock() }; return urls }

    func installedApplicationURL(forBundleIdentifier bundleID: String) -> URL? {
        hasChrome && bundleID == "com.google.Chrome" ? chromeURL : nil
    }
    func isApplicationRunning(bundleIdentifier bundleID: String) -> Bool { false }
    func openApplication(at url: URL) async throws {}
    func openApplication(at url: URL, arguments: [String]) async throws {
        record(arguments)
    }
    func openURL(_ url: URL) async throws {
        recordURL(url)
    }
    func open(paths: [URL], withApplicationAt applicationURL: URL) async throws {
        recordDocuments(paths)
    }

    // Non-async so the lock is taken outside an async context, matching `record` below.
    private func recordURL(_ url: URL) {
        lock.lock(); urls.append(url); lock.unlock()
    }

    private func recordDocuments(_ paths: [URL]) {
        lock.lock(); documents.append(contentsOf: paths); lock.unlock()
    }

    private func record(_ arguments: [String]) {
        lock.lock(); launches.append(arguments); lock.unlock()
    }
}

@Test("first open launches Chrome in the profile and remembers the new window")
func launcherFirstOpenLaunchesAndRemembers() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting() // nothing open yet
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setWindows([99], front: 99) } // the launch's window appears
    )

    let outcome = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com"))
    #expect(outcome == .launched)
    // A new window is forced (--new-window) so the bucket never shares another's window.
    #expect(workspace.recordedLaunches == [["--new-window", "--profile-directory=Profile 1", "https://mail.google.com"]])
}

@Test("the same profile in different modes gets separate windows (NIC-143 follow-up)")
func launcherTracksModesIndependently() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: {
            let existing = scripting.openWindowIDs()
            let next = (existing.max() ?? 10) + 1
            scripting.setWindows(existing + [next], front: next)
        }
    )
    // Same profile, two modes → two launches, two windows.
    _ = try await launcher.open(mode: "developer", profile: "Work", url: nil)       // window 11
    _ = try await launcher.open(mode: "entertainment", profile: "Work", url: nil)   // window 12
    scripting.resetCalls()

    // Re-opening Work in developer focuses window 11, not entertainment's 12.
    _ = try await launcher.open(mode: "developer", profile: "Work", url: nil)
    #expect(scripting.recordedFocusCalls == [11])
    #expect(workspace.recordedLaunches.count == 2)  // no third launch

    // A profile-less open in a mode is its own bucket too.
    _ = try await launcher.open(mode: "developer", profile: nil, url: URL(string: "https://youtube.com"))
    #expect(workspace.recordedLaunches.last == ["--new-window", "https://youtube.com"])
}

@Test("a second open with the window live but no matching tab opens a tab there — no new launch")
func launcherReusesLiveWindow() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setWindows([99], front: 99) }
    )
    _ = try await launcher.open(profile: "Profile 1", url: nil) // records window 99
    scripting.resetCalls()

    let outcome = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com"))
    #expect(outcome == .openedTab)
    #expect(workspace.recordedLaunches.count == 1) // still just the first launch
    #expect(scripting.recordedTabs.map(\.url) == [URL(string: "https://mail.google.com")!])
    #expect(scripting.recordedFocusedTabs.isEmpty) // nothing to surface
}

@Test("a PRE-EXISTING profile window (no new window on launch) is identified by the opened tab, so surfacing engages (NIC-151)")
func launcherRecordsReusedExistingWindow() async throws {
    let workspace = LauncherWorkspace()
    // The profile's window (77) is ALREADY open — the common case Nick hit. The launch
    // adds a tab to it rather than creating a new window; Chrome brings it frontmost and
    // the tab appears. Capture must recognize 77 as the profile's window by that tab,
    // NOT require a brand-new window.
    let scripting = FakeChromeScripting(windowIDs: [77], front: 77)
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setTabs([(1, "https://mail.google.com/mail/u/0/")], inWindow: 77) }
    )
    _ = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com")) // records 77 by content
    scripting.resetCalls()

    // Second open must now surface the existing Gmail tab in window 77 — not relaunch.
    let outcome = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com"))
    #expect(outcome == .surfacedExistingTab)
    #expect(scripting.recordedFocusedTabs.map(\.index) == [1])
    #expect(workspace.recordedLaunches.count == 1) // only the first launch
}

@Test("a matching tab in the profile window is surfaced, not duplicated (NIC-151)")
func launcherSurfacesMatchingTabInProfileWindow() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setWindows([99], front: 99) }
    )
    _ = try await launcher.open(profile: "Profile 1", url: nil) // records window 99
    // The profile window already has a Gmail tab (on a different route/subdomain).
    scripting.setTabs([(1, "https://github.com/"), (2, "https://mail.google.com/mail/u/0/#inbox")], inWindow: 99)
    scripting.resetCalls()

    let outcome = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com"))
    #expect(outcome == .surfacedExistingTab)
    #expect(scripting.recordedFocusedTabs.map(\.index) == [2]) // focused the Gmail tab
    #expect(scripting.recordedTabs.isEmpty) // no duplicate tab opened
    #expect(workspace.recordedLaunches.count == 1) // no new launch
}

@Test("a matching tab in a DIFFERENT profile's window is never surfaced (NIC-151)")
func launcherIgnoresOtherProfileTabs() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setWindows(scripting.openWindowIDs() + [(scripting.openWindowIDs().max() ?? 10) + 1], front: (scripting.openWindowIDs().max() ?? 10) + 1) }
    )
    _ = try await launcher.open(profile: "Profile 1", url: nil) // Work → window 11
    // A Gmail tab exists in ANOTHER (untracked) window — a different profile.
    scripting.setTabs([(1, "https://mail.google.com/")], inWindow: 999)
    scripting.resetCalls()

    // Opening Gmail for Work must not surface the other profile's Gmail tab.
    let outcome = try await launcher.open(profile: "Profile 1", url: URL(string: "https://mail.google.com"))
    #expect(outcome == .openedTab) // opened in Work's own window, not surfaced elsewhere
    #expect(scripting.recordedFocusedTabs.isEmpty)
    #expect(scripting.recordedTabs.map(\.window) == [11]) // Work's window
}

@Test("a remembered window that has closed triggers a fresh launch")
func launcherRelaunchesWhenWindowClosed() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: { scripting.setWindows([99], front: 99) }
    )
    _ = try await launcher.open(profile: "Profile 1", url: nil) // records 99
    scripting.setWindows([], front: nil) // the user closed it

    let outcome = try await launcher.open(profile: "Profile 1", url: nil)
    #expect(outcome == .launched) // relaunched, not reused
    #expect(workspace.recordedLaunches.count == 2)
}

@Test("distinct profiles are remembered independently")
func launcherTracksProfilesIndependently() async throws {
    let workspace = LauncherWorkspace()
    let scripting = FakeChromeScripting()
    let launcher = ChromeProfileLauncher(
        workspace: workspace, scripting: scripting,
        settle: {
            // Each launch adds a new window whose id is one past the highest so far.
            let existing = scripting.openWindowIDs()
            let next = (existing.max() ?? 10) + 1
            scripting.setWindows(existing + [next], front: next)
        }
    )
    _ = try await launcher.open(profile: "Profile 1", url: nil) // window 11
    _ = try await launcher.open(profile: "Default", url: nil) // window 12
    scripting.resetCalls()

    // Re-opening Work focuses window 11, not Default's 12.
    _ = try await launcher.open(profile: "Profile 1", url: nil)
    #expect(scripting.recordedFocusCalls == [11])
    #expect(workspace.recordedLaunches.count == 2) // no third launch
}

@Test("the launcher fails honestly when Chrome is not installed")
func launcherWithoutChromeFails() async throws {
    let workspace = LauncherWorkspace(hasChrome: false)
    let launcher = ChromeProfileLauncher(workspace: workspace, scripting: FakeChromeScripting(), settle: {})
    await #expect(throws: NativeCapabilityError.self) {
        _ = try await launcher.open(profile: "Profile 1", url: nil)
    }
}
#endif
