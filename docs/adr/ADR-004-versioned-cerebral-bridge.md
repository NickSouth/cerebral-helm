# ADR-004: Versioned CerebralBridge with mock Pre-Mac transport and WKWebView macOS transport

- Status: Accepted
- Date: 2026-06-24

## Context

The dashboard must work in the current Pre-Mac phase and later inside the native macOS shell without forking UI logic by transport. The product requires the same production React dashboard to load offline, receive bootstrap state, submit commands, display event-driven state, and degrade clearly when the bridge or platform is incompatible.

The MVP PRD locks:

- a `CerebralBridge` interface between dashboard and runtime;
- `MockCerebralBridge` in Pre-Mac development;
- a `WKWebView` transport on macOS;
- handshake messages that include bridge version, UI version, core version, capabilities, and degraded features;
- recovery UI on incompatible major versions instead of silent continuation.

The tech stack locks the native bridge to WebKit message handlers plus Swift `Codable` messages, and requires that React components not branch on transport.

## Decision

Use one versioned `CerebralBridge` contract across all dashboard environments.

The bridge contract will:

- expose the same required operations in Pre-Mac and macOS environments;
- carry versioned request, response, event, and capability messages;
- start with a handshake that reports bridge, UI, and core versions plus capability and degradation metadata;
- keep React components transport-agnostic.

Pre-Mac development will use a mock bridge implementation for deterministic dashboard work. The macOS target will provide the same contract through `WKWebView` message handlers and Swift `Codable` DTOs.

## Alternatives considered

### Direct dashboard imports of native or filesystem APIs

Rejected because the dashboard boundary explicitly forbids importing native, filesystem, process, database, model, or provider APIs directly.

### Separate bridge APIs for Pre-Mac and macOS

Rejected because that would force the dashboard to branch on environment and would undermine the goal of moving the same production UI from mock transport to native transport.

### Unversioned message passing

Rejected because the PRD and tech stack require stable versioned contracts and explicit compatibility handling. Silent drift would make startup recovery, update safety, and UI degradation much harder to reason about.

## Consequences

### Positive

- The same dashboard can run against mock and native transports without changing component logic.
- Compatibility failures become explicit and recoverable through handshake behavior instead of undefined runtime drift.
- Native capabilities can be exposed incrementally through capability flags and degraded-feature reporting.
- Browser tests and fixtures can exercise the same semantic bridge contract used by the macOS shell.

### Negative

- Bridge schemas and compatibility rules must be maintained deliberately as the product evolves.
- Native and mock transports must stay behaviorally aligned, which adds contract-test pressure.

### Follow-on implications

- Contract generation and compatibility manifest work will build on this bridge versioning model.
- Startup checks must include bridge compatibility before accepting writes.
- Future iOS or remote surfaces may reuse the same semantic contract, but cannot create a parallel dashboard API that bypasses handshake and capability reporting.
