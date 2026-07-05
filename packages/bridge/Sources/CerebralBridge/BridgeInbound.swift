import Foundation
import CerebralContracts

/// A classified inbound bridge message. Only well-formed, known-type, known-operation
/// messages become `.handshake` / `.operation`; everything else is `.malformed` and
/// must be dropped, so a malformed message can never reach core execution
/// (FR-SHL-06 / NIC-74 AC).
public enum BridgeInboundMessage {
    case handshake(CerebralHelmBridgeHandshakeRequest)
    case operation(CerebralHelmBridgeOperationRequest)
    case malformed(reason: String)
}

/// The transport-agnostic inbound gate. Codable decoding enforces the contract's
/// required fields and closed enums (an unknown `operation` value fails to decode),
/// so structural validation happens before any core call.
public enum BridgeInbound {
    /// Reject anything larger than this before parsing (defensive backstop; real
    /// bridge messages are small).
    public static let maxMessageBytes = 512 * 1024

    public static func classify(_ data: Data, maxBytes: Int = maxMessageBytes) -> BridgeInboundMessage {
        guard data.count <= maxBytes else {
            return .malformed(reason: "Message exceeds \(maxBytes) bytes.")
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let type = dictionary["type"] as? String
        else {
            return .malformed(reason: "Message is not a bridge message object with a string \"type\".")
        }

        switch type {
        case CerebralHelmBridgeHandshakeRequestType.bridgeHandshakeRequest.rawValue:
            guard let request = try? CerebralHelmBridgeHandshakeRequest(data: data) else {
                return .malformed(reason: "Malformed handshake request.")
            }
            return .handshake(request)

        case CerebralHelmBridgeOperationRequestType.bridgeOperationRequest.rawValue:
            guard let request = try? CerebralHelmBridgeOperationRequest(data: data) else {
                return .malformed(reason: "Malformed or unknown-operation request.")
            }
            return .operation(request)

        default:
            return .malformed(reason: "Unknown message type: \(type).")
        }
    }
}
