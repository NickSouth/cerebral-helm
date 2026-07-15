// NIC-143: the window navigator's per-window enumeration + actions. The live AX calls
// are verified on the macOS host (manual list); these cover the capability's grouping,
// trust gate, and id→process resolution through the ``AppWindowsSurface`` seam.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

/// A fake ``AppWindowsSurface`` that serves fixed apps/windows and records the
/// `(action, windowID, pid)` it was asked to perform, so the capability's logic is
/// testable without any Accessibility API.
private final class FakeAppWindowsSurface: AppWindowsSurface, @unchecked Sendable {
    let trusted: Bool
    let apps: [AXAppProcess]
    let windowsByPID: [pid_t: [AXWindowRecord]]
    private(set) var actions: [(String, UInt32, pid_t)] = []

    init(trusted: Bool = true, apps: [AXAppProcess], windowsByPID: [pid_t: [AXWindowRecord]]) {
        self.trusted = trusted
        self.apps = apps
        self.windowsByPID = windowsByPID
    }

    var isProcessTrusted: Bool { trusted }
    func regularApplications() -> [AXAppProcess] { apps }
    func windows(pid: pid_t) -> [AXWindowRecord] { windowsByPID[pid] ?? [] }
    func setMinimized(_ minimized: Bool, windowID: UInt32, pid: pid_t) -> Bool {
        actions.append(("minimize:\(minimized)", windowID, pid)); return true
    }
    func raise(windowID: UInt32, pid: pid_t) -> Bool {
        actions.append(("raise", windowID, pid)); return true
    }
    func close(windowID: UInt32, pid: pid_t) -> Bool {
        actions.append(("close", windowID, pid)); return true
    }
}

private func fixtureSurface(trusted: Bool = true) -> FakeAppWindowsSurface {
    FakeAppWindowsSurface(
        trusted: trusted,
        apps: [
            AXAppProcess(pid: 10, bundleID: "com.google.Chrome", appName: "Google Chrome"),
            AXAppProcess(pid: 20, bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code"),
            AXAppProcess(pid: 30, bundleID: "com.apple.finder", appName: "Finder"),
        ],
        windowsByPID: [
            10: [
                AXWindowRecord(windowID: 1001, pid: 10, title: "Inbox", minimized: false),
                AXWindowRecord(windowID: 1002, pid: 10, title: "GitHub", minimized: true),
            ],
            20: [AXWindowRecord(windowID: 2001, pid: 20, title: "main.swift", minimized: false)],
            30: [],  // an app with no on-screen window is dropped from the inventory
        ]
    )
}

@Test("listWindows groups windows by app and drops apps with none (NIC-143)")
func listWindowsGroups() async throws {
    let capability = MacAppWindowsCapability(surface: fixtureSurface())
    let groups = try await capability.listWindows()
    #expect(groups.map(\.bundleID) == ["com.google.Chrome", "com.microsoft.VSCode"])
    #expect(groups.first?.windows.map(\.id) == ["1001", "1002"])
    #expect(groups.first?.windows.last?.minimized == true)
    #expect(groups.first?.appName == "Google Chrome")
}

@Test("without Accessibility trust, listWindows is a permission error, never a prompt (FR-SAF-07)")
func listWindowsUntrustedThrows() async throws {
    let capability = MacAppWindowsCapability(surface: fixtureSurface(trusted: false))
    await #expect(throws: NativeCapabilityError.permissionDenied) {
        _ = try await capability.listWindows()
    }
}

@Test("a window action resolves the owning process by id and performs it (NIC-143)")
func windowActionResolvesProcess() async throws {
    let surface = fixtureSurface()
    let capability = MacAppWindowsCapability(surface: surface)

    #expect(try await capability.minimize(windowID: "1002"))
    #expect(try await capability.surface(windowID: "2001"))
    #expect(try await capability.close(windowID: "1001"))

    #expect(surface.actions.count == 3)
    #expect(surface.actions[0] == ("minimize:true", 1002, 10))
    #expect(surface.actions[1] == ("raise", 2001, 20))
    #expect(surface.actions[2] == ("close", 1001, 10))
}

@Test("an unknown or non-numeric window id is a false result, never an error")
func windowActionUnknownIsFalse() async throws {
    let surface = fixtureSurface()
    let capability = MacAppWindowsCapability(surface: surface)
    #expect(try await !capability.minimize(windowID: "9999"))
    #expect(try await !capability.close(windowID: "not-a-number"))
    #expect(surface.actions.isEmpty)
}
#endif
