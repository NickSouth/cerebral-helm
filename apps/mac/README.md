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
  Resources. Currently shows a placeholder window reporting the resolved paths.
- **Next:** startup validation + read-only recovery view (NIC-72 part 2), then
  dashboard hosting (NIC-73) and the bridge (NIC-74).

## Build & run

The app target links the local Swift package (`../..`) for `CerebralCore`. Build
through the shared scheme (package-dependency builds need a scheme, not `-target`):

```sh
cd apps/mac
xcodebuild -project CerebralHelm.xcodeproj -scheme CerebralHelm \
  -configuration Debug -destination 'platform=macOS' build
```

Or open `CerebralHelm.xcodeproj` in Xcode and Run. Signing is not required for a
local run (code-signing, entitlements/sandbox, notarization, and packaging are a
later epic). The portable Swift packages continue to build and test with plain
`swift test` at the repo root — the Xcode project is macOS-only and additive.
