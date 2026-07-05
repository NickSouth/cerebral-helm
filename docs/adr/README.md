# Architecture decision records

**Owner:** Architecture

**Purpose:** Store numbered decisions with context, alternatives, consequences, and status.

Current records:

- [ADR-001](ADR-001-appkit-wkwebview-shell.md): AppKit shell with `WKWebView` dashboard host
- [ADR-002](ADR-002-single-command-lifecycle.md): Single command bus and immutable lifecycle
- [ADR-003](ADR-003-internal-tool-registry-and-risk-policy.md): Internal tool registry with policy-owned risk and confirmation
- [ADR-004](ADR-004-versioned-cerebral-bridge.md): Versioned `CerebralBridge` with mock Pre-Mac and `WKWebView` macOS transports
- [ADR-005](ADR-005-vendored-sqlite-engine.md): Vendored SQLite via `swift-toolchain-sqlite` (GRDB deferred to post-Mac)
- [ADR-006](ADR-006-sqlite-single-source-of-truth.md): SQLite as the single source of truth for operational history (NDJSON/file adapters demoted)
- [ADR-007](ADR-007-executive-default-mode.md): Executive is the default mode (`config/defaults/app.json` is the single authority; frontend/fixtures aligned)
- [ADR-008](ADR-008-unsandboxed-developer-id-distribution.md): Unsandboxed Developer ID distribution for the MVP (App Sandbox rejected; policy layer remains the security boundary)
