import Foundation
import CerebralContracts

/// Who determined an invocation's arguments (docs/quick-actions/PLAN.md).
///
/// This is a **third permission dimension**, deliberately separate from risk:
///
/// - **Risk** is a property of the *tool* — what the action does. Unchanged by this type.
/// - **Provenance** is a property of the *invocation* — who chose the values it runs with.
/// - The descriptor's `confirmationPolicyKey` decides whether a tool honours a
///   user-authored exemption at all.
///
/// The motivating case: a user who types a message and presses Send has already
/// authored and reviewed exactly what will happen, so a second confirmation restates
/// what they just wrote. A model that says "book it near noon" and picks 12:15 has not —
/// the user never saw 12:15, so it must be disclosed and confirmed.
///
/// ## Why the runtime derives this, and a caller never supplies it
///
/// Provenance is computed here from the ``CommandEnvelope``'s source. It is deliberately
/// **not** a field on any tool input, workflow step, or confirmation payload. If a caller
/// could set it, a model could simply claim `userAuthored` for its own proposals — which is
/// precisely the bypass FR-SAF-02 exists to prevent. The set of sources that count as
/// user-authored is fixed in code below, and nothing a tool receives can influence it.
///
/// The guarantee this provides is scoped honestly: an input surface declares its own source
/// (a trusted first-party surface saying "I am the dashboard"), and the runtime decides what
/// that source *means*. A model choosing tool arguments never touches either value.
public enum ActionProvenance: String, Sendable, Equatable {
    /// The user determined the arguments directly — they typed them, or pressed a control
    /// whose effect was fully described before they pressed it.
    case userAuthored = "user_authored"
    /// A model (or an unattended trigger) determined the arguments. The strict default.
    case modelProposed = "model_proposed"
}

public extension ActionProvenance {
    /// Classifies a command's source. Exhaustive **by design** — there is no `default`, so
    /// adding a new ``CerebralHelmCommandEnvelopeSource`` fails to compile until someone
    /// decides which side of this line it falls on. Silently inheriting `userAuthored`
    /// would be a confirmation bypass introduced by omission.
    init(source: CerebralHelmCommandEnvelopeSource) {
        switch source {
        // A human acting directly on a surface that exists today, where the arguments are
        // what they typed or what the control's label said it would do.
        case .dashboard, .hotkey, .cli:
            self = .userAuthored

        // `agent` and `automation` are the model/unattended paths this distinction exists for.
        // `system` is internal machinery with no human at the keyboard.
        // `voice` is a human *intent* turned into concrete arguments by a model — the
        //   "book it near noon" → 12:15 case — so the values still need disclosing.
        // `ios` is an unbuilt surface: it stays strict until it actually ships and someone
        //   deliberately classifies it, rather than being pre-authorized in absentia.
        case .agent, .automation, .system, .voice, .ios:
            self = .modelProposed
        }
    }
}
