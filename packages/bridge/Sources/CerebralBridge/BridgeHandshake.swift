import Foundation
import CerebralContracts

/// The honest pre-adapter capability set the native shell reports (FR-SHL-06).
///
/// The bridge/bootstrap capability is native; the Mac-only tool and metric
/// capabilities are reported `unavailable` until their adapters land in later epics,
/// so the dashboard degrades honestly (renders them as unavailable) rather than
/// pretending they work. Later epics flip these to `available` / `native`.
public enum BridgeCapabilities {
    public static func preAdapterDefault() -> [Capability] {
        [
            Capability(available: true, degradedReason: nil, id: "bridge.bootstrap", source: .native),
            unavailable("native.app.open", "Opening applications is not available yet."),
            unavailable("native.url.open", "Opening URLs is not available yet."),
            unavailable("native.hook.run", "Running configured hooks is not available yet."),
            unavailable("system.metrics", "Live system metrics are not available yet."),
            unavailable("weather", "Weather is not available yet."),
            unavailable("battery", "Battery status is not available yet.")
        ]
    }

    private static func unavailable(_ id: String, _ reason: String) -> Capability {
        Capability(available: false, degradedReason: reason, id: id, source: .unavailable)
    }
}

/// Builds the versioned handshake response (ADR-004).
///
/// A compatible handshake reports capabilities and derives its degraded features
/// from the unavailable ones (`startupMode` is `ready` when nothing is degraded,
/// otherwise `degraded`). An incompatible handshake returns an empty capability set,
/// `startupMode: recovery`, and a populated `recovery` block so the dashboard shows
/// the read-only recovery screen instead of continuing (matching the
/// `handshake-response` schema's compatible/recovery invariants).
public enum BridgeHandshake {
    public static func response(
        to request: CerebralHelmBridgeHandshakeRequest,
        capabilities: [Capability] = BridgeCapabilities.preAdapterDefault(),
        bridgeVersion: String = BridgeVersions.bridge,
        coreVersion: String = BridgeVersions.core,
        messageID: String
    ) -> CerebralHelmBridgeHandshakeResponse {
        let compatibility = BridgeCompatibility.evaluate(
            bridgeVersion: bridgeVersion,
            supportedBridgeMajor: request.supportedBridgeMajor,
            supportedBridgeMinorFloor: request.supportedBridgeMinorFloor
        )

        guard compatibility.compatible else {
            let reason = compatibility.reason ?? "The bridge version is incompatible."
            return CerebralHelmBridgeHandshakeResponse(
                bridgeVersion: bridgeVersion,
                capabilities: [],
                compatible: false,
                coreVersion: coreVersion,
                degradedFeatures: [
                    DegradedFeature(fallbackUIState: .error, id: "bridge", reason: reason)
                ],
                messageID: messageID,
                recovery: Recovery(
                    diagnosticCode: "bridge_major_version_mismatch",
                    readOnly: true,
                    reason: .majorVersionMismatch,
                    remediation: "Update CerebralHelm so the native app and the dashboard share a compatible bridge version."
                ),
                schemaVersion: BridgeVersions.schema,
                startupMode: .recovery,
                transport: .wkwebview,
                type: .bridgeHandshakeResponse,
                uiVersion: request.uiVersion
            )
        }

        let degradedFeatures = capabilities
            .filter { !$0.available }
            .map { capability in
                DegradedFeature(
                    fallbackUIState: fallback(for: capability.id),
                    id: capability.id,
                    reason: capability.degradedReason ?? "This capability is unavailable."
                )
            }

        return CerebralHelmBridgeHandshakeResponse(
            bridgeVersion: bridgeVersion,
            capabilities: capabilities,
            compatible: true,
            coreVersion: coreVersion,
            degradedFeatures: degradedFeatures,
            messageID: messageID,
            recovery: nil,
            schemaVersion: BridgeVersions.schema,
            startupMode: degradedFeatures.isEmpty ? .ready : .degraded,
            transport: .wkwebview,
            type: .bridgeHandshakeResponse,
            uiVersion: request.uiVersion
        )
    }

    /// Metric-like capabilities fall back to `stale` (last-known values remain
    /// meaningful); everything else falls back to `unavailable`.
    private static func fallback(for capabilityID: String) -> FallbackUIState {
        let metricLike = ["metric", "weather", "battery", "network"]
        return metricLike.contains { capabilityID.contains($0) } ? .stale : .unavailable
    }
}
