import AppKit
import CerebralContracts

/// The dedicated confirmation surface (backdrop-policy decision, 2026-07-06).
///
/// The dashboard is a strict backdrop and never rises above normal windows, so a
/// pending policy-owned disclosure gets its own floating panel — "a pending
/// confirmation must be seen" (NIC-76 AC3) is satisfied by this window, not by
/// lifting the dashboard. The panel renders the disclosure **verbatim** and never
/// classifies risk itself (FR-SAF); sensitive argument values are redacted. Only
/// approve/cancel exist here — the bridge fails anything else closed as cancel —
/// and Cancel always owns the return key (`defaultFocusedChoice` can only ever be
/// the safe side), so approval requires an explicit click.
///
/// One decision per panel: deciding disables the buttons, and the panel closes
/// when the runtime clears the confirmation (`confirmation: null`), keeping this
/// surface and the dashboard's web overlay consistent.
///
/// `@unchecked Sendable`: created and used only on the main thread —
/// `WindowCoordinator.deliverBridgeEvent` hops to main before any window work
/// (the same discipline as the coordinator itself); the annotation lets `self`
/// serve as the buttons' target under strict concurrency.
final class ConfirmationWindowController: NSObject, @unchecked Sendable {
    private let panel: NSPanel
    private var decided = false
    private var buttons: [NSButton] = []
    private let disclosureID: String
    private let onDecision: (String, String) -> Void

    init(disclosure: CerebralHelmConfirmationDisclosure, onDecision: @escaping (String, String) -> Void) {
        disclosureID = disclosure.id
        self.onDecision = onDecision
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Confirmation Required"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init()
        panel.contentView = makeContent(disclosure)
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    /// The confirmation was resolved or invalidated (decided here, in the web
    /// overlay, or expired) — this surface goes away.
    func close() {
        panel.orderOut(nil)
    }

    // MARK: - Content

    private func makeContent(_ disclosure: CerebralHelmConfirmationDisclosure) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        stack.addArrangedSubview(label(disclosure.actionSummary, .boldSystemFont(ofSize: 14)))
        stack.addArrangedSubview(label(
            "Risk: \(readable(disclosure.risk.rawValue)) · \(readable(disclosure.reversibility.rawValue)) · data leaving device: \(readable(disclosure.dataLeavingDevice.rawValue))",
            .systemFont(ofSize: 11), color: .secondaryLabelColor
        ))
        stack.addArrangedSubview(label(disclosure.policyReason, .systemFont(ofSize: 12)))
        stack.addArrangedSubview(label(
            "Tool: \(disclosure.tool.id) \(disclosure.tool.version)",
            .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor
        ))
        if let destination = disclosure.destination, !destination.isEmpty {
            stack.addArrangedSubview(label(
                "Destination: \(destination)",
                .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor
            ))
        }
        for argument in disclosure.arguments {
            let value = argument.sensitive ? "•••" : argument.value
            stack.addArrangedSubview(label(
                "\(argument.name): \(value)",
                .monospacedSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor
            ))
        }

        let cancel = NSButton(
            title: disclosure.choices.cancel.label, target: self, action: #selector(cancelTapped)
        )
        cancel.keyEquivalent = "\r"
        let approve = NSButton(
            title: disclosure.choices.approve.label, target: self, action: #selector(approveTapped)
        )
        buttons = [cancel, approve]

        let buttonRow = NSStackView(views: [NSView(), cancel, approve])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        stack.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true

        // Long summaries/paths wrap inside a fixed panel width instead of growing it.
        stack.widthAnchor.constraint(equalToConstant: 460).isActive = true
        return stack
    }

    private func label(_ text: String, _ font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.isSelectable = false
        return field
    }

    /// Contract enum raw values are snake_case; render them as words.
    private func readable(_ rawValue: String) -> String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Decisions (single-use)

    @objc private func approveTapped() {
        decide("approve")
    }

    @objc private func cancelTapped() {
        decide("cancel")
    }

    private func decide(_ decision: String) {
        guard !decided else { return }
        decided = true
        for button in buttons {
            button.isEnabled = false
        }
        onDecision(disclosureID, decision)
    }
}
