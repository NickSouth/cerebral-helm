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

    /// Binds the shared ``BridgeSession`` composed once at the app layer
    /// (`AppBridgeRuntime`). Both the dashboard and the command-palette transport bind
    /// the *same* session, so operations from either webview run against one live
    /// runtime (NIC-75 / FR-SHL-02) rather than forking a second one.
    func bind(session: BridgeSession) {
        self.session = session
    }

    /// Delivers an already-encoded bridge-event JSON to *this* webview. The app routes
    /// the shared session's event stream here for the dashboard transport (the palette
    /// transport is not registered as an event sink — it only submits).
    func deliverBridgeEvent(_ json: String) {
        deliverEncoded(json)
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
            // Report the capability flags composed at the app layer (FR-SHL-06);
            // before a session is bound, fall back to the honest pre-adapter set.
            let capabilities = session?.capabilities ?? BridgeCapabilities.preAdapterDefault()
            let response = BridgeHandshake.response(to: request, capabilities: capabilities, messageID: Self.newMessageID())
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
        guard let payload = try? BridgeMessageCoding.encoder().encode(message),
              let json = String(data: payload, encoding: .utf8) else {
            log.error("Failed to encode bridge reply.")
            return
        }
        deliverEncoded(json)
    }

    /// Hands an already-encoded bridge-message JSON to the dashboard's receive
    /// callback. Takes a Sendable `String` so the @Sendable event-forwarding closure
    /// can call it without sending a non-Sendable DTO across threads.
    private func deliverEncoded(_ json: String) {
        // Re-encode the JSON string as a JS string literal so quotes/newlines are safe.
        guard let literal = try? JSONEncoder().encode(json),
              let literalString = String(data: literal, encoding: .utf8) else { return }
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
