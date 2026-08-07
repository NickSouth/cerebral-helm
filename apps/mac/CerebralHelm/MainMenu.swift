import AppKit

/// The app's main menu, built programmatically (the shell uses no MainMenu.xib —
/// ADR-001).
///
/// The point is the **Edit menu**: macOS delivers the standard editing shortcuts
/// (⌘Z/⌘X/⌘C/⌘V/⌘A) only through an Edit menu's items, routed down the responder
/// chain to the first responder. Without one, paste and friends never reach the
/// hosted WKWebView text fields — the URL pin field, the command bar, settings —
/// even though typing works (the backdrop can become key). A minimal App menu
/// (Hide/Quit) rounds out the bar for this `.regular` app.
enum MainMenu {
    static func install(appName: String) {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        // nil target → the item's action travels the responder chain to whatever
        // holds first responder (the focused WKWebView), which performs the edit.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
