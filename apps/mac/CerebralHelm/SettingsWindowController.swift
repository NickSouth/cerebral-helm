import AppKit
import KeyboardShortcuts

/// The native settings window for the command-palette shortcut (NIC-75 / FR-SHL-02).
///
/// Hotkey registration is a native concern (`KeyboardShortcuts`, Carbon-backed), so its
/// configuration lives here rather than in the web dashboard. `KeyboardShortcuts.RecorderCocoa`
/// lets the user rebind or clear (disable) the shortcut and flags in-app conflicts as you
/// record; the remediation copy covers the system-wide case the recorder cannot detect.
/// The window is created lazily and reused.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm Settings"
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        window.contentView = Self.makeContent()
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeContent() -> NSView {
        let heading = label("Command palette shortcut", size: 15, weight: .semibold)
        let subtitle = label(
            "Press this shortcut from anywhere to summon the command palette.",
            size: 12, secondary: true
        )

        let recorderRow = NSStackView(views: [
            label("Shortcut", size: 13),
            KeyboardShortcuts.RecorderCocoa(for: .summonPalette)
        ])
        recorderRow.orientation = .horizontal
        recorderRow.spacing = 12

        let remediation = label(
            "If the shortcut doesn’t respond, another app may already use it — pick a "
                + "different combination, or clear it to disable. The default is ⌥Space.",
            size: 11, secondary: true
        )

        let stack = NSStackView(views: [heading, subtitle, recorderRow, remediation])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func label(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.preferredMaxLayoutWidth = 400
        return field
    }
}
