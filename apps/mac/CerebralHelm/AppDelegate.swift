import AppKit
import CerebralCore

/// The macOS application lifecycle owner (NIC-72 / FR-SHL-01).
///
/// For this first increment the shell launches offline, resolves the explicit
/// personal-production state root *outside* the app bundle via the portable core
/// (`WorkspacePaths.forApplication`), ensures that root exists, and shows a
/// placeholder window reporting the resolved locations. Startup validation and the
/// read-only recovery view arrive in NIC-72 part 2; dashboard hosting and the
/// bridge follow in NIC-73/NIC-74.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow(with: resolveWorkspace())
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Resolves workspace paths through the portable core and creates the writable
    /// state root. Read-only config resolves from the app bundle's Resources; user
    /// state lives at `~/Library/Application Support/CerebralHelm`, never inside the
    /// `.app` (NIC-72). Returns a human-readable report for the placeholder window.
    private func resolveWorkspace() -> String {
        guard let resources = Bundle.main.resourceURL else {
            return "Startup error: could not locate the app bundle Resources directory."
        }
        do {
            let paths = try WorkspacePaths.forApplication(bundleResourcesRoot: resources)
            try FileManager.default.createDirectory(
                at: paths.stateRoot, withIntermediateDirectories: true
            )
            return """
            CerebralHelm — native shell
            NIC-72 · MAC-SHELL-1

            Launched offline. User data lives outside the app bundle.

            Environment:  \(paths.environment.rawValue)

            State root (writable):
              \(paths.stateRoot.path)

            Config (read-only, bundled):
              \(paths.configDirectory.path)

            Operational database:
              \(paths.operationalDatabasePath.path)
            """
        } catch {
            return "Startup error: failed to resolve workspace paths.\n\n\(error)"
        }
    }

    private func showWindow(with text: String) {
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
        self.window = window
    }
}
