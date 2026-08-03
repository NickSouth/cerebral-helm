# ADR-003: Internal tool registry with policy-owned risk and confirmation

- Status: Accepted
- Date: 2026-06-24

## Context

CerebralHelm must execute a narrow set of deterministic tools while remaining useful before any model or broad automation layer exists. The product explicitly rejects arbitrary shell access and requires deterministic confirmation behavior outside model discretion.

The MVP PRD locks:

- one internal tool registry;
- provider-neutral semantic tool names;
- declared risk classes for every tool;
- confirmation determined by policy, not by callers or models;
- exact hook allowlists rather than free-form shell text;
- visible tool activity, confirmations, and structured failures.

The tech stack further recommends:

- an internal Swift registry with MCP-shaped JSON Schemas;
- tool descriptors that include version, timeout, cancellation behavior, redaction rules, and structured results;
- no required MCP transport in the MVP.

## Decision

Use an internal tool registry as the single source of truth for executable capability contracts, and make risk classification plus confirmation policy an owned responsibility of the policy layer rather than of callers, tools, or models.

Every registered tool descriptor will include:

- stable semantic name and semantic version;
- versioned input and output schemas;
- exactly one declared risk class;
- timeout, cancellation, retry, and idempotency metadata;
- required capability and permission metadata;
- structured result shapes and redaction rules.

The registry remains internal in the MVP, even though descriptors are MCP-shaped. Tool execution may not be reached through arbitrary shell text or provider-specific shortcuts.

## Alternatives considered

### Ad hoc tool invocation from UI or native code

Rejected because it would scatter risk and capability decisions across presentation and adapter layers, violating the locked boundary that the registry owns capability contracts and the policy engine owns confirmation.

### Direct MCP transport as the MVP extension system

Rejected because the MVP does not require an MCP transport and must not load arbitrary third-party code into the application process. The internal registry is the locked starting point.

### Model-selected risk classes or confirmation bypass

Rejected because the PRD explicitly forbids a model from lowering risk, bypassing confirmation, or directly invoking platform capability.

## Consequences

### Positive

- Tool behavior, risk, timeout, and redaction become inspectable and testable in one place.
- UI, shell, and future model layers can reason about capabilities without owning the execution rules.
- Future MCP support can be added at the registry boundary rather than by replacing the product architecture.
- Hook execution remains narrow, allowlisted, and auditable.

### Negative

- New tools require descriptor work up front rather than informal one-off execution.
- Some future integrations may feel slower to prototype because they must fit registry and policy contracts first.

### Follow-on implications

- Config, fixtures, and future schema work must preserve semantic tool naming rather than implementation-specific names.
- Risk aggregation for multi-step plans such as mode application must remain at least as strict as the highest planned action.
- Future provider or transport decisions may extend the registry boundary, but cannot relocate confirmation authority outside policy.
- Confirmation gained a second, orthogonal input — **provenance**, whether the user or a model determined an invocation's arguments ([quick actions plan](../quick-actions/PLAN.md)). This refines the rejected alternative above rather than reopening it: the descriptor still declares whether a tool may be exempted at all, the exemption reaches only the `external_write` class, and provenance is derived by the runtime from the command source rather than declared by a caller — so a model still cannot lower risk or bypass confirmation for its own proposals.
