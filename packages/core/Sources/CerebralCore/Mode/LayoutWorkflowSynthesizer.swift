import Foundation
import CerebralContracts

/// Synthesizes a mode's `open-<mode>-layout` workflow from its authored `layout`
/// (NIC-142).
///
/// A layout is *windows-only*: each static window and the quick-toggle slot's
/// initially-shown target become an `app.open` / `url.open` step, and every
/// app-kind window (which resolves to a bundle id) is arranged into its named
/// frame by a single trailing `window.arrange` step. The result is an ordinary
/// ``CerebralHelmWorkflowDefinition`` — opening a layout is a normal quick-action
/// workflow of narrow, individually-policed tool steps (one aggregate
/// confirmation, per-step disclosure and progress), never a monolithic tool that
/// would hide which apps, URLs, and windows it touches.
///
/// The whole arrangement targets `layout.display` (primary / secondary), passed
/// through to the `window.arrange` step; the platform adapter resolves each frame
/// against that display, degrading to the primary display when the secondary is
/// absent.
///
/// One deliberate limitation, honest about the current primitives:
/// - **URL windows are opened but not arranged.** `window.arrange` targets an
///   application's main window by bundle id; a URL reference is not an app, so a
///   URL entry's frame is carried in the contract but not applied here. Browser
///   window/tab placement is a later increment.
public enum LayoutWorkflowSynthesizer {
    /// The workflow id a mode's layout resolves to: `open-<modeID>-layout`.
    public static func workflowID(modeID: String) -> String { "open-\(modeID)-layout" }

    /// Builds the ordered open + arrange workflow for `modeID`'s authored `layout`.
    public static func workflow(modeID: String, layout: Layout) throws -> CerebralHelmWorkflowDefinition {
        var steps: [Step] = []
        var arrangement: [Arrangement] = []

        for (index, window) in layout.windows.enumerated() {
            steps.append(try openStep(id: "open-window-\(index)", ref: window.ref, kind: window.kind))
            if window.kind == .app {
                arrangement.append(Arrangement(appID: window.ref, frame: window.frame))
            }
        }

        // The quick-toggle slot's first target is the initially-shown window; the
        // remaining targets are surfaced on demand from the bottom bar (NIC-142
        // toggle increment), so opening the layout only opens the first.
        if let toggle = layout.quickToggle, let first = toggle.targets.first {
            steps.append(try openStep(id: "open-toggle", ref: first.ref, kind: first.kind))
            if first.kind == .app {
                arrangement.append(Arrangement(appID: first.ref, frame: toggle.frame))
            }
        }

        if !arrangement.isEmpty {
            steps.append(Step(
                id: "arrange-windows",
                input: try inputObject(CerebralHelmWindowArrangeInput(arrangement: arrangement, display: layout.display)),
                label: "Arrange layout windows",
                tool: "window.arrange"
            ))
        }

        return CerebralHelmWorkflowDefinition(
            extensions: nil,
            id: workflowID(modeID: modeID),
            label: "Open \(modeID.capitalized) Layout",
            schemaVersion: "1.0.0",
            steps: steps
        )
    }

    private static func openStep(id: String, ref: String, kind: Kind) throws -> Step {
        switch kind {
        case .app:
            return Step(id: id, input: try inputObject(CerebralHelmAppOpenInput(appID: ref)),
                        label: "Open \(ref)", tool: "app.open")
        case .url:
            return Step(id: id, input: try inputObject(CerebralHelmURLOpenInput(urlID: ref)),
                        label: "Open \(ref)", tool: "url.open")
        }
    }

    /// Renders a typed tool input as a workflow step's `[String: JSONAny]` binding
    /// by round-tripping through JSON, so the synthesized step carries exactly the
    /// JSON each tool's input schema expects (the same bytes a hand-authored
    /// workflow file would).
    private static func inputObject<T: Encodable>(_ value: T) throws -> [String: JSONAny] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode([String: JSONAny].self, from: data)
    }
}
