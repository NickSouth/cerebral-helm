import Foundation

/// A parsed `major.minor.patch` semantic version.
public struct BridgeSemanticVersion: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

/// The version identity the native bridge advertises in its handshake (ADR-004).
/// `schema` is the bridge *message* schema version; `bridge` is this transport's
/// contract version (its major gates compatibility); `core` mirrors the runtime.
public enum BridgeVersions {
    public static let schema = "1.0.0"
    public static let bridge = "1.0.0"
    public static let core = "0.1.0"
}

/// The deterministic version-compatibility decision (FR-SHL-06, ADR-004).
///
/// The dashboard's handshake request declares the bridge major it was built against
/// and the minimum bridge minor it needs. The native bridge is compatible only when
/// its major matches and its minor is at or above that floor; otherwise the shell
/// enters read-only recovery rather than continuing on a mismatched contract.
public struct BridgeCompatibility: Equatable, Sendable {
    public let compatible: Bool
    /// A human-readable explanation when incompatible; `nil` when compatible.
    public let reason: String?

    public static func evaluate(
        bridgeVersion: String,
        supportedBridgeMajor: Int,
        supportedBridgeMinorFloor: Int
    ) -> BridgeCompatibility {
        guard let version = BridgeSemanticVersion(bridgeVersion) else {
            return BridgeCompatibility(
                compatible: false,
                reason: "Bridge version \"\(bridgeVersion)\" is not a valid semantic version."
            )
        }
        if version.major != supportedBridgeMajor {
            return BridgeCompatibility(
                compatible: false,
                reason: "Bridge major version \(version.major) is incompatible with UI-supported major version \(supportedBridgeMajor)."
            )
        }
        if version.minor < supportedBridgeMinorFloor {
            return BridgeCompatibility(
                compatible: false,
                reason: "Bridge minor version \(version.minor) is below the UI-required minimum \(supportedBridgeMinorFloor)."
            )
        }
        return BridgeCompatibility(compatible: true, reason: nil)
    }
}
