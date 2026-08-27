import Foundation

/// Where the context a caller is assembling is about to go (NIC-254).
///
/// Every profile today resolves to a local runtime, so in practice this is always ``local``. The
/// type exists anyway, and the policy below is enforced anyway, because the point is not what it
/// filters out today — it is that the mechanism is built, tested and trusted **before** a cloud
/// escape hatch is ever opened. A filter written the day it first matters is a filter nobody has
/// ever seen work.
public enum ModelDestination: Equatable, Sendable {
    /// Inference on this machine. Nothing leaves it.
    case local
    /// A provider off the machine. None exists yet; ADR-009 keeps any future one off by default and
    /// confirmation-gated.
    case cloud
}

/// Whether a piece of durable knowledge may be put in front of a model (NIC-254).
///
/// Two levers, doing different jobs. ``NoteMetadata`` `cloudPolicy` answers *may this leave the
/// machine*, so it gates on destination. `sensitivity` answers *how private is this*, and one tier
/// of it — `secret` — is treated as "not model context at all", which is what gives the strongest
/// label teeth: a user who marks a note secret has said more than "be careful with this".
///
/// Both default the safe way when absent, matching the note schema's own rule that `cloudPolicy`
/// defaults to deny and never to allow.
public enum ModelContextPolicy {
    /// The verdict on one note, carrying why. The reason is for tests and for an operator-facing
    /// explanation of a thin brief — never for the model, which is told nothing about what was
    /// withheld.
    public enum Admission: Equatable, Sendable {
        case admitted
        case excluded(reason: String)

        public var isAdmitted: Bool { self == .admitted }
    }

    /// Whether a note carrying this frontmatter may go to `destination`.
    ///
    /// Values arrive as the raw strings the note's frontmatter carries, unparsed, because that is
    /// what ``KnowledgeService`` surfaces and because an unrecognised value must be treated as
    /// stricter than the strictest known one rather than silently ignored.
    public static func admits(
        sensitivity: String?,
        cloudPolicy: String?,
        to destination: ModelDestination
    ) -> Admission {
        let sensitivityValue = normalized(sensitivity)
        let policyValue = normalized(cloudPolicy)

        // `secret` is withheld from every destination, this machine included. The other three tiers
        // describe how careful to be with a note; this one says do not surface it, and a local model
        // composing it into a brief on screen is surfacing it.
        if sensitivityValue == "secret" {
            return .excluded(reason: "sensitivity is secret")
        }
        // An unrecognised sensitivity is treated as secret rather than as private: a vocabulary this
        // build does not know is one added later, and guessing the lenient way is how a stricter
        // future tier would leak on an older build.
        if let sensitivityValue, !knownSensitivities.contains(sensitivityValue) {
            return .excluded(reason: "sensitivity \u{201C}\(sensitivityValue)\u{201D} is not recognised")
        }

        switch destination {
        case .local:
            // Nothing leaves the machine, so `cloudPolicy` has nothing to say here. Recorded
            // explicitly rather than by falling through, so the reason this is safe is written down
            // next to the code that relies on it.
            return .admitted
        case .cloud:
            // Absent defaults to deny, per the note schema — never to allow.
            guard policyValue == "allow" else {
                return .excluded(reason: "cloudPolicy is \(policyValue ?? "unset (defaults to deny)")")
            }
            return .admitted
        }
    }

    static let knownSensitivities: Set<String> = ["public", "private", "sensitive", "secret"]

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
