import Testing

import CerebralContracts
import CerebralCore

/// NIC-30 (PRE-SAFETY-3): deterministic risk and confirmation policy.
///
/// AC-30.1 all seven risk classes covered; AC-30.2 callers cannot lower risk;
/// AC-30.3 exact hook allowlist rules tested. Also covers `highest_planned_action`
/// aggregation (FR-MOD-03) and stricter-only configured overrides (PRD §10.3).

@Test("every risk class has a deterministic baseline decision (AC-30.1)")
func everyRiskClassIsCovered() {
    let engine = PolicyEngine()
    let expected: [(Risk, PolicyDecision)] = [
        (.readOnly, .allow),
        (.localWrite, .requireConfirmation),
        (.externalWrite, .requireConfirmation),
        (.destructive, .requireConfirmation),
        (.shell, .requireConfirmation),
        (.financial, .requireConfirmation),
        (.purchaseOrBooking, .requireConfirmation),
    ]

    // Guards that the table actually spans all seven declared classes.
    #expect(Set(expected.map(\.0)).count == 7)

    for (risk, decision) in expected {
        let evaluation = engine.evaluate(PolicyRequest(toolID: "tool.under_test", declaredRisk: risk))
        #expect(evaluation.decision == decision, "\(risk.rawValue)")
        #expect(evaluation.governingRisk == risk, "\(risk.rawValue)")
    }
}

@Test("a caller cannot lower a required confirmation but may raise one (AC-30.2)")
func callersCannotLowerRisk() {
    let engine = PolicyEngine()

    // Asking to skip confirmation is ignored for any confirming class.
    let localWrite = engine.evaluate(
        PolicyRequest(toolID: "app.open", declaredRisk: .localWrite, callerRequestedConfirmation: false)
    )
    #expect(localWrite.decision == .requireConfirmation)

    let shell = engine.evaluate(
        PolicyRequest(toolID: "hook.run", declaredRisk: .shell, callerRequestedConfirmation: false)
    )
    #expect(shell.decision == .requireConfirmation)

    // A caller may always raise: read-only plus requested confirmation escalates.
    let readOnly = engine.evaluate(
        PolicyRequest(toolID: "note.search", declaredRisk: .readOnly, callerRequestedConfirmation: true)
    )
    #expect(readOnly.decision == .requireConfirmation)
    #expect(readOnly.reasonCode == "confirm.caller_requested")
}

@Test("shell runs without confirmation only on an exact allowlist match (AC-30.3)")
func exactHookAllowlistMatch() {
    let trusted = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: ["CI": "true"]
    )
    let engine = PolicyEngine(hookAllowlist: HookAllowlist(entries: [trusted]))

    func decision(for invocation: HookInvocation) -> PolicyDecision {
        engine.evaluate(
            PolicyRequest(toolID: "hook.run", declaredRisk: .shell, shellInvocation: invocation)
        ).decision
    }

    // Exact match is the only path to allow.
    #expect(decision(for: trusted) == .allow)

    // Any variation in executable, arguments, working directory, or environment
    // invalidates the match.
    #expect(decision(for: HookInvocation(executable: "/usr/bin/make", arguments: ["build"], workingDirectory: "/repo", environment: ["CI": "true"])) == .requireConfirmation)
    #expect(decision(for: HookInvocation(executable: "/usr/bin/just", arguments: ["test"], workingDirectory: "/repo", environment: ["CI": "true"])) == .requireConfirmation)
    #expect(decision(for: HookInvocation(executable: "/usr/bin/just", arguments: ["build"], workingDirectory: "/elsewhere", environment: ["CI": "true"])) == .requireConfirmation)
    #expect(decision(for: HookInvocation(executable: "/usr/bin/just", arguments: ["build"], workingDirectory: "/repo", environment: [:])) == .requireConfirmation)

    // A shell tool with no resolved invocation can never be allowlisted.
    #expect(engine.evaluate(PolicyRequest(toolID: "hook.run", declaredRisk: .shell)).decision == .requireConfirmation)
}

@Test("configured overrides may escalate but never relax (AC-30.2, stricter-only)")
func overridesAreStricterOnly() {
    let trusted = HookInvocation(executable: "/bin/x", arguments: [], workingDirectory: "/", environment: [:])

    // Escalating shell to deny beats even an exact allowlist match.
    let denyShell = PolicyEngine(
        overrides: PolicyOverrides(minimumDecisions: [.shell: .deny]),
        hookAllowlist: HookAllowlist(entries: [trusted])
    )
    #expect(denyShell.evaluate(PolicyRequest(toolID: "hook.run", declaredRisk: .shell, shellInvocation: trusted)).decision == .deny)

    // An override of `.allow` cannot relax a class that already confirms.
    let relax = PolicyEngine(overrides: PolicyOverrides(minimumDecisions: [.localWrite: .allow]))
    #expect(relax.evaluate(PolicyRequest(toolID: "app.open", declaredRisk: .localWrite)).decision == .requireConfirmation)

    // The provisional MVP hard-denial set denies deferred classes outright...
    let mvp = PolicyEngine(overrides: .mvpHardDenials)
    #expect(mvp.evaluate(PolicyRequest(toolID: "x", declaredRisk: .destructive)).decision == .deny)
    #expect(mvp.evaluate(PolicyRequest(toolID: "x", declaredRisk: .financial)).decision == .deny)
    #expect(mvp.evaluate(PolicyRequest(toolID: "x", declaredRisk: .purchaseOrBooking)).decision == .deny)
    // ...without over-reaching into implemented classes.
    #expect(mvp.evaluate(PolicyRequest(toolID: "x", declaredRisk: .localWrite)).decision == .requireConfirmation)
}

@Test("a plan aggregates to at least the strictest planned action (FR-MOD-03)")
func highestPlannedActionAggregates() {
    let engine = PolicyEngine()

    // mode.apply is declared local_write, but its plan contains a shell action.
    let withShell = engine.evaluate(
        PolicyRequest(
            toolID: "mode.apply",
            declaredRisk: .localWrite,
            runtimeRiskPolicy: .highestPlannedAction,
            plannedActionRisks: [.readOnly, .localWrite, .shell]
        )
    )
    #expect(withShell.decision == .requireConfirmation)
    #expect(withShell.governingRisk == .shell)

    // An all-read plan stays allow.
    let allRead = engine.evaluate(
        PolicyRequest(
            toolID: "mode.apply",
            declaredRisk: .readOnly,
            runtimeRiskPolicy: .highestPlannedAction,
            plannedActionRisks: [.readOnly]
        )
    )
    #expect(allRead.decision == .allow)
    #expect(allRead.governingRisk == .readOnly)

    // A deny override on any planned-action class propagates to the aggregate.
    let mvp = PolicyEngine(overrides: .mvpHardDenials)
    let denied = mvp.evaluate(
        PolicyRequest(
            toolID: "mode.apply",
            declaredRisk: .localWrite,
            runtimeRiskPolicy: .highestPlannedAction,
            plannedActionRisks: [.localWrite, .destructive]
        )
    )
    #expect(denied.decision == .deny)
}

@Test("evaluation is deterministic for a fixed request")
func evaluationIsDeterministic() {
    let engine = PolicyEngine(overrides: .mvpHardDenials, hookAllowlist: HookAllowlist())
    let request = PolicyRequest(toolID: "hook.run", declaredRisk: .shell)
    #expect(engine.evaluate(request) == engine.evaluate(request))
}
