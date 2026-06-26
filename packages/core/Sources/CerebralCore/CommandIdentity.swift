/// Validates command, event, and correlation identifiers against the contract
/// patterns (`^cmd_…`, `^evt_…`, `^(cmd|corr)_…` with an 8–64 character suffix
/// from `[A-Za-z0-9_-]`). Validation is implemented directly rather than with a
/// regex engine so it behaves identically across platforms.
public enum CommandIdentity {
    /// `true` when `value` is a valid command identifier (`cmd_…`).
    public static func isValidCommandIdentifier(_ value: String) -> Bool {
        hasValidForm(value, prefixes: ["cmd"])
    }

    /// `true` when `value` is a valid event identifier (`evt_…`).
    public static func isValidEventIdentifier(_ value: String) -> Bool {
        hasValidForm(value, prefixes: ["evt"])
    }

    /// `true` when `value` is a valid correlation identifier (`cmd_…` or `corr_…`).
    public static func isValidCorrelationIdentifier(_ value: String) -> Bool {
        hasValidForm(value, prefixes: ["cmd", "corr"])
    }

    private static func hasValidForm(_ value: String, prefixes: [String]) -> Bool {
        for prefix in prefixes {
            let token = prefix + "_"
            guard value.hasPrefix(token) else { continue }
            let suffix = value.dropFirst(token.count)
            if (8...64).contains(suffix.count) && suffix.allSatisfy(isAllowed) {
                return true
            }
        }
        return false
    }

    private static func isAllowed(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}
