import Foundation
import CerebralContracts
import CerebralCore

/// `window.arrange` (NIC-88): move configured applications' main windows into
/// named frames through the window capability.
///
/// Applications resolve through the same reference catalog as `app.open` — an
/// unknown id is an honest per-entry result, never an arbitrary bundle target.
/// Every entry reports individually (FR-MOD-04 partial semantics): not running,
/// no controllable window, and per-entry failures degrade the overall status to
/// `partial` without aborting the rest. A denied Accessibility permission is a
/// capability error for the whole call (FR-SAF-07) — the executor reports it as
/// `denied` and nothing retries or prompts.
public struct WindowArrangeHandler: ToolHandler {
    public let toolID = "window.arrange"
    private let capability: any WindowCapability
    /// Configured app references: id → bundle identifier (the `app.open` catalog).
    private let appTargets: [String: String]

    public init(capability: any WindowCapability, appTargets: [String: String]) {
        self.capability = capability
        self.appTargets = appTargets
    }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmWindowArrangeInput
        do { decoded = try CerebralHelmWindowArrangeInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("window.arrange input does not match its contract.")
        }

        // The display targets the whole arrangement (NIC-142 layout mode); an
        // absent value keeps the pre-existing primary-display behavior.
        let display: WindowDisplay = decoded.display == .secondary ? .secondary : .primary

        var entries: [Entry] = []
        for item in decoded.arrangement {
            entries.append(try await arrange(item, display: display))
        }

        let allArranged = entries.allSatisfy { $0.status == .arranged }
        return try CerebralHelmWindowArrangeOutput(
            entries: entries,
            status: allArranged ? .arranged : .partial
        ).jsonData()
    }

    private func arrange(_ item: Arrangement, display: WindowDisplay) async throws -> Entry {
        guard let bundleID = appTargets[item.appID] else {
            return entry(item, .unknownApp, "'\(item.appID)' is not a configured app reference.")
        }
        guard let frame = WindowFrame(rawValue: item.frame.rawValue) else {
            // Unreachable behind the schema's enum; kept as an honest guard.
            return entry(item, .failed, "Unknown frame '\(item.frame.rawValue)'.")
        }
        do {
            switch try await capability.arrange(bundleID: bundleID, frame: frame, display: display) {
            case .arranged:
                return entry(item, .arranged, nil)
            case .notRunning:
                return entry(item, .notRunning, "Not running; windows are only arranged, never launched.")
            case let .unsupported(reason):
                return entry(item, .unsupported, reason)
            }
        } catch NativeCapabilityError.permissionDenied {
            // Accessibility trust is process-level: the whole call is denied
            // (FR-SAF-07), reported as a capability error with guidance — never
            // a per-entry partial and never a re-prompt.
            throw ToolHandlerError.permissionDenied(
                "Window arrangement needs the Accessibility permission. Grant it in System Settings → Privacy & Security → Accessibility."
            )
        } catch NativeCapabilityError.unavailable {
            throw ToolHandlerError.unavailable("Window arrangement is available on the macOS host.")
        } catch {
            return entry(item, .failed, "Arranging failed for this application.")
        }
    }

    private func entry(_ item: Arrangement, _ status: EntryStatus, _ message: String?) -> Entry {
        Entry(appID: item.appID, frame: item.frame.rawValue, message: message, status: status)
    }
}
