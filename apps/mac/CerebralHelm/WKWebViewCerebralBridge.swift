import Foundation
import WebKit
import CerebralBridge
import CerebralContracts
import CerebralCore
import CerebralRuntimeHost
import os

/// The macOS `WKWebView` transport for the versioned CerebralBridge (NIC-74, ADR-004).
///
/// The dashboard posts JSON bridge messages to
/// `window.webkit.messageHandlers.cerebral` and receives replies through the
/// `window.__cerebralReceive(json)` callback it installs. This increment implements
/// the **handshake** — version compatibility and capability reporting — and drops
/// malformed messages before they reach core (the classification gate lives in the
/// portable `CerebralBridge` package). Mapping operations onto the live
/// `CommandRuntime` and pushing the event stream land in the next increment; until
/// then an operation is answered with an `unavailable_capability` error so the
/// dashboard degrades honestly rather than hanging. React components never branch on
/// transport (ADR-004).
final class WKWebViewCerebralBridge: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    static let handlerName = "cerebral"

    private weak var webView: WKWebView?
    private var session: BridgeSession?
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "bridge")

    /// Registers the message handler on a configuration before the web view is built.
    func install(on configuration: WKWebViewConfiguration) {
        configuration.userContentController.add(self, name: Self.handlerName)
    }

    /// Binds the web view used to deliver replies (set right after construction).
    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    /// Builds the live runtime for this session so bridge operations execute against
    /// it (NIC-74b). The startup pre-flight has already validated config + the
    /// database, so composition is expected to succeed; if it does not, operations
    /// answer with a structured error rather than crashing.
    func connectRuntime(paths: WorkspacePaths) {
        session = (try? makeCommandRuntime(paths: paths)).map(BridgeSession.init(runtime:))
        if session == nil { log.error("Bridge runtime composition failed; operations will report unavailable.") }
    }

    func userContentController(
        _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        guard let json = message.body as? String, let data = json.data(using: .utf8) else {
            log.error("Bridge message body was not a JSON string; dropped.")
            return
        }

        switch BridgeInbound.classify(data) {
        case let .handshake(request):
            let response = BridgeHandshake.response(to: request, messageID: Self.newMessageID())
            log.info("Bridge handshake: ui=\(request.uiVersion, privacy: .public) compatible=\(response.compatible, privacy: .public) startup=\(response.startupMode.rawValue, privacy: .public)")
            deliver(response)

        case let .operation(request):
            guard let session else {
                deliver(Self.runtimeUnavailable(for: request))
                return
            }
            // Send only the Sendable JSON across the task boundary (the decoded DTO
            // holds a reference-typed payload and is not Sendable); re-decode inside.
            // The runtime call is async; reply on completion so the dashboard never
            // hangs. `deliver` marshals back to the main thread for evaluateJavaScript.
            let requestData = data
            Task { [weak self] in
                guard let request = try? CerebralHelmBridgeOperationRequest(data: requestData) else { return }
                let response = await session.execute(request)
                self?.deliver(response)
            }

        case let .malformed(reason):
            log.error("Rejected malformed bridge message: \(reason, privacy: .public)")
        }
    }

    /// Encodes a message to JSON and hands it to the dashboard's receive callback.
    private func deliver<Message: Encodable>(_ message: Message) {
        guard
            let payload = try? JSONEncoder().encode(message),
            let payloadString = String(data: payload, encoding: .utf8),
            // Re-encode the JSON string as a JS string literal so quotes/newlines are safe.
            let literal = try? JSONEncoder().encode(payloadString),
            let literalString = String(data: literal, encoding: .utf8)
        else {
            log.error("Failed to encode bridge reply.")
            return
        }
        let script = "window.__cerebralReceive && window.__cerebralReceive(\(literalString));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script)
        }
    }

    private static func runtimeUnavailable(
        for request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: CerebralHelmBridgeOperationResponseError(
                category: .unavailableCapability,
                code: "bridge_runtime_unavailable",
                details: nil,
                message: "The runtime is unavailable; restart CerebralHelm.",
                remediation: nil
            ),
            messageID: request.messageID,
            operation: request.operation,
            payload: [:],
            schemaVersion: BridgeVersions.schema,
            status: .error,
            type: .bridgeOperationResponse
        )
    }

    private static func newMessageID() -> String {
        "brmsg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}
