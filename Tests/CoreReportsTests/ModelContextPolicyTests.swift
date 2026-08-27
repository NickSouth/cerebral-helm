import Foundation
import Testing
@testable import CerebralCore

/// NIC-254: what may be put in front of a model, and where it may go.
///
/// Inference is local, so **nothing these tests exclude is excluded in production today**. That is
/// the point rather than an objection: the filter has to exist, be exercised and be trusted before a
/// cloud escape hatch is ever opened, and a filter written the day it first matters is one nobody
/// has ever seen work. Every cloud case below is the behaviour that switch would depend on.

private func admits(
    sensitivity: String? = "sensitive",
    cloudPolicy: String? = "deny",
    to destination: ModelDestination
) -> ModelContextPolicy.Admission {
    ModelContextPolicy.admits(sensitivity: sensitivity, cloudPolicy: cloudPolicy, to: destination)
}

// MARK: - Local

@Test("a cloudPolicy of deny is no obstacle to a model running on this machine")
func denyIsAdmittedLocally() {
    // `cloudPolicy` answers "may this leave the machine". Locally nothing does, so it has nothing to
    // say — which is exactly why profile notes default to deny and are still usable here.
    #expect(admits(cloudPolicy: "deny", to: .local).isAdmitted)
    #expect(admits(cloudPolicy: "ask", to: .local).isAdmitted)
    #expect(admits(cloudPolicy: nil, to: .local).isAdmitted)
    #expect(admits(sensitivity: "private", to: .local).isAdmitted)
    #expect(admits(sensitivity: "public", to: .local).isAdmitted)
}

@Test("secret is withheld from every destination, this machine included")
func secretIsNeverModelContext() {
    // The other three tiers say how careful to be with a note. This one says do not surface it — and
    // a local model composing it into a brief on screen IS surfacing it. Marking a note secret
    // should mean more than "be careful".
    #expect(!admits(sensitivity: "secret", to: .local).isAdmitted)
    #expect(!admits(sensitivity: "secret", cloudPolicy: "allow", to: .cloud).isAdmitted)

    guard case let .excluded(reason) = admits(sensitivity: "secret", to: .local) else {
        Issue.record("a secret note must be excluded")
        return
    }
    #expect(reason.contains("secret"))
}

// MARK: - Cloud

@Test("only an explicit allow reaches a cloud provider")
func cloudRequiresExplicitAllow() {
    #expect(admits(cloudPolicy: "allow", to: .cloud).isAdmitted)
    #expect(!admits(cloudPolicy: "deny", to: .cloud).isAdmitted)
    // `ask` means a per-note choice nobody has made yet, and assembling context is not the moment to
    // ask — so it is excluded rather than treated as permission.
    #expect(!admits(cloudPolicy: "ask", to: .cloud).isAdmitted)
}

@Test("an absent cloudPolicy defaults to deny, never to allow")
func absentPolicyDefaultsToDeny() {
    // The note schema's own rule: "Defaults to deny; never defaults to allow." A note written by
    // hand in Obsidian, with no frontmatter at all, must not become the exception.
    #expect(!admits(cloudPolicy: nil, to: .cloud).isAdmitted)
    #expect(!admits(cloudPolicy: "", to: .cloud).isAdmitted)
    #expect(!admits(cloudPolicy: "   ", to: .cloud).isAdmitted)

    guard case let .excluded(reason) = admits(cloudPolicy: nil, to: .cloud) else {
        Issue.record("an unset policy must be excluded from cloud")
        return
    }
    #expect(reason.contains("defaults to deny"))
}

// MARK: - Values this build does not know

@Test("an unrecognised sensitivity is treated as the strictest, not the most lenient")
func unknownSensitivityIsExcluded() {
    // A vocabulary this build does not know is one added later. Guessing the lenient way is how a
    // stricter future tier leaks on an older build — the failure mode that only shows up after the
    // tier is introduced, on machines nobody is looking at.
    #expect(!admits(sensitivity: "restricted", to: .local).isAdmitted)
    #expect(!admits(sensitivity: "top-secret", cloudPolicy: "allow", to: .cloud).isAdmitted)
    #expect(ModelContextPolicy.knownSensitivities == ["public", "private", "sensitive", "secret"])
}

@Test("an unrecognised cloudPolicy is not an allow")
func unknownPolicyIsNotAllow() {
    // Only the exact string `allow` opens the gate; anything else, known or not, keeps it shut.
    #expect(!admits(cloudPolicy: "permitted", to: .cloud).isAdmitted)
    #expect(!admits(cloudPolicy: "yes", to: .cloud).isAdmitted)
}

@Test("frontmatter is matched without regard to case or stray whitespace")
func valuesAreNormalised() {
    // These are hand-written YAML values in files the user edits in Obsidian. "Secret" and " deny "
    // are what people actually type, and a filter that only recognised the canonical spelling would
    // silently stop applying the moment someone capitalised it.
    #expect(!admits(sensitivity: "  SECRET ", to: .local).isAdmitted)
    #expect(admits(cloudPolicy: " Allow ", to: .cloud).isAdmitted)
    #expect(admits(sensitivity: "Sensitive", to: .local).isAdmitted)
}
