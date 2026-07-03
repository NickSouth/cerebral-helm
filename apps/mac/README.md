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
  pre-adapter degraded state. The runtime **event stream** is forwarded too: every
  command lifecycle event is pushed to the dashboard as a `command.lifecycle.transition`
  bridge event (`BridgeEventFactory` + a shared ISO-8601 encoder). `searchNotes`
  runs through the bus and returns live index hits; `getRecentActivity` returns the
  honest empty envelope (durable history read is a follow-on). The **confirmation
  flow** is wired: a gated command pushes a `confirmation.changed` disclosure event,
  and `decideConfirmation` looks up the single-use token and resolves it (approve /
  cancel) with a clearing event. `updateSettings` validates the patch against the
  deterministic allowlist (`SettingsPatchValidator`) — policy-weakening keys are
  rejected (ADR-003); durable persistence is a follow-on (no settings store yet).
  The operation surface is complete except `captureNote` (a contract tension — it
  returns a synchronous `noteId` but `note.capture` is confirmation-gated; notes are
  capturable today via `submitCommand`).
- **NIC-74c (done):** the dashboard runs on the **live bridge**. The dashboard-side
  `wkWebViewCerebralBridge` implements `CerebralBridge` over
  `window.webkit.messageHandlers.cerebral` ↔ `window.__cerebralReceive` (operations
  correlated by messageId, events dispatched to subscribers); `createDashboardRuntime`
  selects it when running inside the shell, seeding synchronously from the bootstrap
  the shell injects (`window.__cerebralBootstrap`). React components are unchanged.
- **NIC-75 (done):** the menu-bar item + global command hotkey + floating command
  palette (FR-SHL-02). `MenuBarController` owns an `NSStatusItem` (summon palette /
  settings / quit) and registers a configurable global hotkey via the Carbon-backed
  `KeyboardShortcuts` package (default ⌥Space, no Accessibility permission). The
  `CommandRuntime` + `BridgeSession` now compose once at the app layer
  (`AppBridgeRuntime`) and are shared: the dashboard **and** the palette submit through
  the one live runtime (no forked runtime). `CommandPaletteWindowController` is a single
  pre-warmed `NSPanel` hosting a lightweight `index.html?surface=palette` WebKit route
  that renders only the existing `CommandSurface`; summon activates + focuses it in
  ~one frame, repeated summon focuses the same panel (no duplicates), and submit /
  Escape / click-away dismiss it via a private `paletteControl` channel.
  `SettingsWindowController` hosts `KeyboardShortcuts.RecorderCocoa` to rebind/disable
  the shortcut with conflict-remediation copy. Deferred to NIC-76: the "Ask Heimlich →
  dashboard center panel" window-role routing and syncing the palette to the active mode.
- **Next:** native window roles / command choreography (NIC-76), then on-device visual
  tuning (NIC-77).

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
