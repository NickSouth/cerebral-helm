# Repository boundaries

**Status:** Active foundation rule  
**Owner:** Architecture  
**Source:** NIC-11, MVP PRD sections 6.1-6.2, NFR-01, and NFR-02

## Dependency direction

```text
apps/dashboard --> generated contract bindings
apps/mac ------> portable core + adapters + generated contract bindings
apps/ios ------> generated remote contract bindings (future)

tools -----> core -----> shared
knowledge --> core -----> shared

all contract consumers --> canonical JSON Schemas
canonical JSON Schemas import no application module
```

The arrows point from a consumer to a dependency. They show allowed knowledge of lower-level boundaries, not permission to bypass contracts. Application surfaces compose behavior. Portable packages own deterministic behavior. Platform, storage, provider, and model implementations remain adapters at application edges.

## Enforced rules

1. `packages/` must compile on non-Mac environments and must not import AppKit.
2. `apps/dashboard/` may import browser-safe UI and bridge modules only. It may not import native, filesystem, process, database, model, or provider APIs.
3. `apps/mac/` is the only MVP location that may own AppKit lifecycle and native platform adapters.
4. `packages/contracts/` is the canonical language-neutral contract boundary; generated code is a consumer, never the source of truth.
5. `config/`, `fixtures/`, and `knowledge-template/` contain distributable defaults or sanitized examples only - never personal production state or secrets.
6. `database/migrations/` changes operational state only. User-authored Markdown remains the durable knowledge source.
7. Production code must not depend on `.agent/`, `docs/`, `wiki/`, or developer scripts at runtime.

The root Swift package and repository boundary tests provide the first compile-time and source-level proof. The standardized commands and CI entry points that run those checks are owned by NIC-12.
