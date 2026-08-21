// Shared wire encoding for the model provider concretes.
#if canImport(AppKit)
import Foundation
import CerebralCore

extension JSONValue {
    /// The `JSONSerialization`-compatible form, so a structural schema or argument object can ride
    /// a request without a second encoding pass.
    ///
    /// Shared rather than per-adapter: every provider concrete has to put a `JSONValue` on the
    /// wire, and two copies of this switch would drift the first time a case is added.
    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case let .bool(value): return value
        case let .number(value): return value
        case let .string(value): return value
        case let .array(values): return values.map(\.anyValue)
        case let .object(values): return values.mapValues(\.anyValue)
        }
    }
}
#endif
