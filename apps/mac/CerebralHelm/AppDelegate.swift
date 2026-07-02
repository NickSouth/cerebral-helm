import AppKit
import CerebralCore

/// The macOS application lifecycle owner (NIC-72 / FR-SHL-01, FR-SHL-05).
///
/// On launch the shell runs a read-only startup pre-flight (`Bootstrap.run`) that
/// validates data paths, the bundled config schemas, and the operational database
/// *before any write*. A clean pre-flight creates the writable state root and shows
/// the main window; a failed pre-flight opens the read-only recovery window and
/// mutates nothing (PRD §8.1). Dashboard hosting and the bridge follow in
/// NIC-73/NIC-74.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var recoveryWindow: RecoveryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch Bootstrap.run() {
        case let .ready(paths):
            enterReady(paths)
        case let .recovery(recovery):
            enterRecovery(recovery)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A clean pre-flight: create the writable state root (the first legitimate
    /// write) and show the main window. If even the state root cannot be created,
    /// fall back to recovery rather than run over a broken location.
    private func enterReady(_ paths: WorkspacePaths) {
        do {
            try FileManager.default.createDirectory(
                at: paths.stateRoot, withIntermediateDirectories: true
            )
        } catch {
            enterRecovery(Bootstrap.Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "state_root_uncreatable",
                remediation: "Grant write access to ~/Library/Application Support, then relaunch.",
                details: ["Could not create the state root at \(paths.stateRoot.path): \(error)"]
            ))
            return
        }
        showMainWindow(with: readyReport(paths))
    }

    private func enterRecovery(_ recovery: Bootstrap.Recovery) {
        let controller = RecoveryWindowController(recovery)
        controller.show()
        recoveryWindow = controller
    }

    private func readyReport(_ paths: WorkspacePaths) -> String {
        """
        CerebralHelm — native shell
        NIC-72 · MAC-SHELL-1

        Startup validation passed. Launched offline; user data lives outside the app bundle.

        Environment:  \(paths.environment.rawValue)

        State root (writable):
          \(paths.stateRoot.path)

        Config (read-only, bundled):
          \(paths.configDirectory.path)

        Operational database:
          \(paths.operationalDatabasePath.path)
        """
    }

    private func showMainWindow(with text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CerebralHelm"
        window.center()

        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = true
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        self.mainWindow = window
    }
}
