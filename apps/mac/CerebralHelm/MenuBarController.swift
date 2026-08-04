import AppKit
import KeyboardShortcuts

/// Owns the menu-bar presence and the global summon hotkey (NIC-75 / FR-SHL-02).
///
/// An `NSStatusItem` gives CerebralHelm a persistent menu-bar affordance — show the sidebar,
/// open settings, quit — and the global `KeyboardShortcuts` hotkey summons the sidebar from
/// anywhere. Both the menu item and the hotkey call the **same** injected closure, so there is
/// exactly one summon entry point; the single-sidebar guarantee is enforced by the controller
/// that closure drives, not here.
///
/// The shortcut's persistence key is still `summonPalette` (see `PaletteShortcut`): it is durable
/// storage that predates the command palette's removal, and renaming it would silently reset every
/// user's existing binding.
///
/// This type is UI wiring only — all behavior is injected by the app layer.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let summonSidebar: () -> Void
    private let openSettings: () -> Void

    init(summonSidebar: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.summonSidebar = summonSidebar
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        statusItem.menu = buildMenu()

        // Global hotkey → the sidebar. onKeyDown (not up) keeps the summon snappy against the
        // ~200ms latency target (FR-SHL-02 AC).
        KeyboardShortcuts.onKeyDown(for: .summonPalette) { [weak self] in
            self?.summonSidebar()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "CerebralHelm")
        button.image?.isTemplate = true
        button.toolTip = "CerebralHelm"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let sidebarItem = NSMenuItem(
            title: "Show Sidebar", action: #selector(summonSidebarAction), keyEquivalent: ""
        )
        sidebarItem.target = self
        menu.addItem(sidebarItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit CerebralHelm", action: #selector(quitAction), keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func summonSidebarAction() { summonSidebar() }
    @objc private func settingsAction() { openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
