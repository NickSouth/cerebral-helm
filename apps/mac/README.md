# macOS application

**Owner:** macOS platform

**Purpose:** Native AppKit application shell — lifecycle owner, WKWebView dashboard
host, versioned bridge transport, window roles, hotkey, and native adapters
(ADR-001). This is the app-layer composition target for the Mac; no portable
package under `packages/` may depend on it.

## Status (NIC-71 / MAC-SHELL)

- **NIC-72 part 1 (done):** Xcode app target, AppKit lifecycle, and explicit data
  paths. The app launches offline and resolves its writable state root *outside*
  the bundle at `~/Library/Application Support/CerebralHelm` via the portable core
  (`WorkspacePaths.forApplication`); read-only config resolves from the bundle
  Resources.
- **NIC-72 part 2 (done):** read-only startup pre-flight (`Bootstrap` →
  `StartupValidation`) that validates data paths, bundled config schemas, and the
  operational database *before any write*; failures open a read-only recovery
  window and mutate nothing.
- **NIC-73 (done):** the bundled production dashboard is hosted in a `WKWebView`,
  loaded offline over the private `cerebral://app/` scheme (`CerebralSchemeHandler`)
  above an `NSVisualEffectView`. Config **and** the dashboard build are bundled into
  Resources; a missing dashboard bundle surfaces as a visible diagnostic.
- **NIC-74a (done):** the versioned bridge transport skeleton. The portable
  `CerebralBridge` package owns the handshake, version compatibility, and the
  inbound-message gate (malformed messages never reach core); the app's
  `WKWebViewCerebralBridge` adapts it to WebKit message handlers
  (`window.webkit.messageHandlers.cerebral` ↔ `window.__cerebralReceive`). The
  handshake reports capabilities and enters recovery on a major-version mismatch.
- **NIC-74b (in progress):** bridge operations now execute against the live
  runtime. The shared `CerebralRuntimeHost` package composes the `CommandRuntime`
  once (the CLI and the shell both use it); `BridgeSession` maps `submitCommand`,
  `applyMode`, and `getBootstrapState` onto it, and the transport routes operations
  through it. `getBootstrapState` composes the four mode views and the agent roster
  from the real config (`BootstrapComposer`), with regions/Heimlich in their honest
  pre-adapter degraded state. Remaining: `captureNote`, `searchNotes`,
  `decideConfirmation`, `updateSettings`, `getRecentActivity`, and the event stream.
- **Next:** finish the operation set + push the event stream, then NIC-74c adds the
  dashboard-side transport and selects it. Until then the dashboard still runs its
  in-webview mock bridge.

## Build & run

The dashboard is a **generated** input: build and stage it before building the app
(no dev server is used — the app serves the static bundle offline):

```sh
apps/mac/scripts/build-dashboard-bundle.sh   # → apps/mac/DashboardBundle/ (gitignored)
```

Then build the app. It links the local Swift package (`../..`) for `CerebralCore`
and `CerebralStorage`; build through the shared scheme (package-dependency builds
need a scheme, not `-target`):

```sh
cd apps/mac
xcodebuild -project CerebralHelm.xcodeproj -scheme CerebralHelm \
  -configuration Debug -destination 'platform=macOS' build
```

Or open `CerebralHelm.xcodeproj` in Xcode and Run. If `DashboardBundle/` is empty
(script not run), the app launches into a "dashboard bundle missing" diagnostic
rather than a blank window. Signing is not required for a local run (code-signing,
entitlements/sandbox, notarization, and packaging are a later epic). The portable
Swift packages continue to build and test with plain `swift test` at the repo
root — the Xcode project is macOS-only and additive.
