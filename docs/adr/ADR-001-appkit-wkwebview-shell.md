# ADR-001: AppKit shell with WKWebView dashboard host

- Status: Accepted
- Date: 2026-06-24

## Context

CerebralHelm needs one native macOS shell that can own lifecycle, windows, menu bar behavior, permissions, focus, displays, startup checks, and future platform adapters without creating a second product architecture beside the dashboard UI.

The MVP PRD locks the shell responsibilities to the native layer and requires:

- explicit window roles for dashboard, bottom bar, command palette, confirmation, and settings;
- bundled offline dashboard assets;
- startup validation before accepting writes;
- capability-aware degradation rather than broken or fake native behavior.

The tech stack locks:

- Swift plus AppKit for the application shell;
- `WKWebView` as the dashboard host;
- `NSVisualEffectView` beneath transparent web content when native visual material is needed;
- no Electron, Tauri, or parallel SwiftUI-first macOS product architecture.

The Pre-Mac foundation must stay portable and non-AppKit-dependent, but the eventual macOS target must still have a clear landing zone that preserves the same command bus, policy, bridge, and storage boundaries.

## Decision

Use a native Swift plus AppKit shell as the only macOS application owner, and host the production React dashboard inside `WKWebView`.

The shell will own:

- application lifecycle and startup validation;
- native window and panel roles;
- bridge transport, capability reporting, and platform event sources;
- native permissions, login-item behavior, and future platform adapters.

The dashboard will remain a bundled web application that renders state and expresses intent through the bridge, without directly owning native APIs or shell policy.

SwiftUI may be introduced later only for isolated native controls where it does not create a competing shell architecture.

## Alternatives considered

### SwiftUI-first shell

Rejected because the current architecture locks AppKit as the primary macOS shell and needs direct, explicit ownership of window roles, focus behavior, and `WKWebView` hosting without introducing a parallel product architecture.

### Electron or Tauri shell

Rejected because the tech stack explicitly excludes them from the MVP baseline. They would also blur the boundary between native authority and dashboard presentation, and would add an unnecessary runtime dependency to a product that already separates Swift authority from React presentation.

### Fully native AppKit views instead of React dashboard hosting

Rejected because the MVP PRD and tech stack already lock the production dashboard to React plus TypeScript, with the bridge boundary preserved between UI and runtime.

## Consequences

### Positive

- Preserves one clear native authority layer for lifecycle, windows, permissions, and platform adapters.
- Keeps the dashboard portable across Pre-Mac and macOS phases by preserving the bridge boundary.
- Supports offline bundled UI loading and deterministic startup validation.
- Avoids rewriting the dashboard when moving from the current machine to macOS.

### Negative

- Requires maintaining two implementation surfaces: native Swift/AppKit and dashboard React/TypeScript.
- Introduces bridge design and verification work that a purely native UI would not need.
- Demands explicit validation on target macOS hardware for window behavior, hotkeys, and native integration details.

### Follow-on implications

- Native-only capabilities must surface through capability flags rather than dashboard imports.
- The shell implementation must remain subordinate to the command bus, policy, update, and storage boundaries already locked by the PRD.
- Future ADRs may refine supporting libraries, but may not replace AppKit plus `WKWebView` with a parallel shell model.
