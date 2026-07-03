import AppKit
import KeyboardShortcuts

/// Owns the menu-bar presence and the global summon hotkey (NIC-75 / FR-SHL-02).
///
/// An `NSStatusItem` gives CerebralHelm a persistent menu-bar affordance — summon the
/// command palette, open settings, quit — and the global `KeyboardShortcuts` hotkey
/// (`.summonPalette`) summons the palette from anywhere. Both the menu item and the
/// hotkey call the **same** injected `summon` closure, so there is exactly one summon
/// entry point; the single-palette guarantee (FR-SHL-02) is enforced by the palette
/// controller that closure drives, not here. This type is UI wiring only — all behavior
/// is injected by the app layer.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let summon: () -> Void
    private let openSettings: () -> Void

    init(summon: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.summon = summon
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        statusItem.menu = buildMenu()

        // Global hotkey → the same summon path as the menu item. onKeyDown (not up) keeps
        // the summon snappy against the ~200ms latency target (FR-SHL-02 AC).
        KeyboardShortcuts.onKeyDown(for: .summonPalette) { [weak self] in
            self?.summon()
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

        let summonItem = NSMenuItem(
            title: "Summon Command Palette", action: #selector(summonAction), keyEquivalent: ""
        )
        summonItem.target = self
        menu.addItem(summonItem)

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

    @objc private func summonAction() { summon() }
    @objc private func settingsAction() { openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
