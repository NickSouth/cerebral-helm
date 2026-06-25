# ADR-002: Single command bus and immutable lifecycle

- Status: Accepted
- Date: 2026-06-24

## Context

CerebralHelm accepts intent from multiple current or future sources: dashboard, hotkey, CLI, automation, system, and later voice, iOS, and agent surfaces. The product requires that these inputs converge on one command system instead of each surface inventing its own execution path.

The MVP PRD locks:

- one command bus for all supported sources;
- one versioned command envelope shape;
- one lifecycle with valid transitions and terminal-state immutability;
- immutable lifecycle events stored for observability;
- deterministic cancellation and confirmation behavior;
- denied confirmations ending as `cancelled`, not `failed`.

The product also requires that lifecycle, confirmation, tool activity, and errors remain visible and testable across UI and storage.

## Decision

Route every user or system intent through a single versioned command bus and a single immutable lifecycle.

The lifecycle is:

- `received`
- `planned`
- `requires_confirmation`
- `running`
- terminal states: `succeeded`, `failed`, `cancelled`

Every transition must emit an immutable event containing command ID, event ID, timestamp, previous status, current status, and optional message or structured error.

All supported input sources must produce the same versioned command envelope and must not bypass planning, policy, lifecycle validation, or event publication.

## Alternatives considered

### Source-specific execution paths

Rejected because they would fragment behavior between dashboard, CLI, hotkey, and future voice or mobile flows. That would break the PRD requirement that inputs converge on one command lifecycle and would make policy and observability inconsistent.

### Immediate tool execution without a planning stage

Rejected because the product requires deterministic planning, aggregate risk evaluation, and confirmation handling before execution. Mode application in particular depends on an explicit ordered plan.

### Mutable in-place command records

Rejected because immutable lifecycle events are required for observability, diagnostics, replay safety, and confirmation auditability.

## Consequences

### Positive

- Every input surface gets the same planning, policy, cancellation, and observability behavior.
- Tests can validate one lifecycle model instead of many surface-specific variants.
- Future sources such as voice or iOS become additive if they can emit the same envelope.
- Dashboard, storage, and native shell can subscribe to the same event stream and reason about the same states.

### Negative

- Even simple actions must fit the same lifecycle model, which adds implementation ceremony compared with direct function calls.
- Source-specific UX must still map cleanly onto the shared lifecycle without adding hidden states.

### Follow-on implications

- Schema and fixtures must cover valid and invalid lifecycle transitions.
- Storage must preserve both command records and immutable command events.
- Confirmation tokens and plan hashes must stay tied to the planned command state rather than ad hoc UI behavior.
