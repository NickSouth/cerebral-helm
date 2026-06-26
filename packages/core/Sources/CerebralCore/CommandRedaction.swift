/// Identifies which command-envelope fields are sensitive, so observability and
/// history layers can redact them (FR-CMD-06, FR-OBS-03).
///
/// This is the envelope-level baseline keyed off declared `privacy.sensitivity`.
/// Per-tool, descriptor-declared `redactionPaths` (ADR-003) will augment this in
/// a later increment; this type does not perform the redaction itself, only
/// identifies the fields that require it.
public enum CommandRedaction {
    /// Top-level envelope field paths considered sensitive for the given command.
    ///
    /// Rule:
    /// - `public`: nothing is sensitive.
    /// - `private`: `payload` (may carry resolved references/arguments); the
    ///   user-facing `rawInput` is not redacted.
    /// - `sensitive` / `secret`: both `rawInput` and `payload` are sensitive.
    public static func sensitiveFieldPaths(for envelope: CommandEnvelope) -> [String] {
        switch envelope.privacy.sensitivity {
        case .sensitivityPublic:
            return []
        case .sensitivityPrivate:
            return ["payload"]
        case .sensitive, .secret:
            return ["rawInput", "payload"]
        }
    }

    /// `true` when any field of the command must be redacted before logging.
    public static func isSensitive(_ envelope: CommandEnvelope) -> Bool {
        !sensitiveFieldPaths(for: envelope).isEmpty
    }
}
