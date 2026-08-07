import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

// NIC-142: a mode's authored `layout` synthesizes into an ordinary open + arrange
// workflow of narrow tool steps. These tests pin the synthesis shape without any
// I/O — the pure heart of layout-open execution.

private func decodeInput<T: Decodable>(_ step: Step, as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(step.input ?? [:])
    return try JSONDecoder().decode(T.self, from: data)
}

@Test("a layout with static windows and a quick-toggle slot synthesizes open + arrange steps")
func synthesizesStaticAndToggle() throws {
    let layout = Layout(
        display: .primary,
        quickToggle: QuickToggle(frame: .leftTwoThirds, targets: [
            Target(kind: .app, ref: "vscode"),
            Target(kind: .url, ref: "github"),
        ]),
        windows: [Window(frame: .rightThird, kind: .app, ref: "claude-desktop")]
    )

    let workflow = try LayoutWorkflowSynthesizer.workflow(modeID: "developer", layout: layout)

    #expect(workflow.id == "open-developer-layout")
    #expect(workflow.steps.map(\.id) == ["open-window-0", "open-toggle", "arrange-windows"])
    #expect(workflow.steps.map(\.tool) == ["app.open", "app.open", "window.arrange"])

    #expect(try decodeInput(workflow.steps[0], as: CerebralHelmAppOpenInput.self).appID == "claude-desktop")
    #expect(try decodeInput(workflow.steps[1], as: CerebralHelmAppOpenInput.self).appID == "vscode")

    // The arrange step covers the static app window plus the toggle's first (app)
    // target, each at its frame.
    let arrange = try decodeInput(workflow.steps[2], as: CerebralHelmWindowArrangeInput.self)
    #expect(arrange.arrangement.map(\.appID) == ["claude-desktop", "vscode"])
    #expect(arrange.arrangement.map { $0.frame.rawValue } == ["right-third", "left-two-thirds"])
    // The whole arrangement targets the layout's display.
    #expect(arrange.display == .primary)
}

@Test("a URL window is opened but not arranged (window.arrange targets an app bundle)")
func urlWindowsOpenedNotArranged() throws {
    let layout = Layout(
        display: .secondary,
        quickToggle: nil,
        windows: [
            Window(frame: .leftHalf, kind: .url, ref: "github"),
            Window(frame: .rightHalf, kind: .app, ref: "vscode"),
        ]
    )

    let workflow = try LayoutWorkflowSynthesizer.workflow(modeID: "developer", layout: layout)

    #expect(workflow.steps.map(\.tool) == ["url.open", "app.open", "window.arrange"])
    #expect(try decodeInput(workflow.steps[0], as: CerebralHelmURLOpenInput.self).urlID == "github")
    // Only the app window reaches the arrange step; the URL window is left out.
    let arrange = try decodeInput(workflow.steps[2], as: CerebralHelmWindowArrangeInput.self)
    #expect(arrange.arrangement.map(\.appID) == ["vscode"])
    // A secondary-display layout carries that target through to the arrange step.
    #expect(arrange.display == .secondary)
}

@Test("a layout with no arrangeable windows synthesizes opens with no arrange step")
func noArrangeableWindowsOmitsArrangeStep() throws {
    let layout = Layout(
        display: .primary,
        quickToggle: QuickToggle(frame: .full, targets: [Target(kind: .url, ref: "github")]),
        windows: [Window(frame: .leftHalf, kind: .url, ref: "docs")]
    )

    let workflow = try LayoutWorkflowSynthesizer.workflow(modeID: "school", layout: layout)

    #expect(workflow.id == "open-school-layout")
    #expect(workflow.steps.map(\.tool) == ["url.open", "url.open"])
    #expect(!workflow.steps.contains { $0.tool == "window.arrange" })
}

@Test("the synthesized workflow id follows the open-<mode>-layout convention")
func workflowIDConvention() {
    #expect(LayoutWorkflowSynthesizer.workflowID(modeID: "entertainment") == "open-entertainment-layout")
}
