import AppKit

/// The read-only startup recovery window (FR-SHL-05, PRD §8.1 step 7).
///
/// Shown when the startup pre-flight fails. It presents the diagnostic and
/// remediation and states plainly that no data was changed — the shell stays
/// read-only and never auto-repairs or discards user data (AC-49.3). It offers no
/// control that could mutate state; the only action is to quit.
final class RecoveryWindowController {
    let window: NSWindow

    init(_ recovery: Bootstrap.Recovery) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm — Recovery"
        window.center()
        window.contentView = RecoveryWindowController.makeContent(recovery)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeContent(_ recovery: Bootstrap.Recovery) -> NSView {
        let title = label("CerebralHelm can’t start safely", .systemFont(ofSize: 20, weight: .semibold))
        let reason = label(humanReason(recovery.reason), .systemFont(ofSize: 13, weight: .regular))

        let remediation = label("What to do: \(recovery.remediation)", .systemFont(ofSize: 13, weight: .medium))
        remediation.textColor = .labelColor

        let details = label(recovery.details.joined(separator: "\n"), .monospacedSystemFont(ofSize: 11, weight: .regular))
        details.textColor = .secondaryLabelColor

        let code = label("Diagnostic code: \(recovery.diagnosticCode)", .monospacedSystemFont(ofSize: 11, weight: .regular))
        code.textColor = .tertiaryLabelColor

        let reassurance = label(
            "Your data was not changed. The app stays read-only until this is resolved — nothing is repaired or deleted automatically.",
            .systemFont(ofSize: 12, weight: .regular)
        )
        reassurance.textColor = .secondaryLabelColor

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.keyEquivalent = "\r"
        quit.bezelStyle = .rounded

        let stack = NSStackView(views: [title, reason, remediation, details, code, reassurance, quit])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        return container
    }

    private static func label(_ text: String, _ font: NSFont) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.isSelectable = true
        return field
    }

    private static func humanReason(_ reason: String) -> String {
        switch reason {
        case "startup_validation_failed":
            return "Startup validation failed, so CerebralHelm did not open your workspace."
        case "major_version_mismatch":
            return "This build is not compatible with your existing data."
        default:
            return reason
        }
    }
}
