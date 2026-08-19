# Model profile configuration

**Owner:** Configuration

**Purpose:** Which model serves each capability profile, how much context it may allocate, and how long it stays resident (ADR-009, NIC-243).

`profiles.json` is **optional**. With no such file the app runs exactly as it does today, because no model is required for the product to work — deterministic commands, quick actions, mode application, note capture, note search, observability, and updates are all model-free.

Product logic asks for a capability profile — `fast`, `balanced`, `deep`, `local` — and never for a model id. That indirection is the point: the default model has already changed once, and no named local model may become an architectural dependency.

Two fields are memory decisions rather than capability ones, and both come from measurement:

- `contextTokens` caps the window. Left to a runtime's own judgement, Ollama allocates the model's **full advertised window** (131K/262K), which took a 21 GB model to 29 GB resident; capping to 16K recovered ~6 GB.
- `residency` decides what stays loaded. `pinned` for an always-on surface, where a ~70 s cold reload would be felt on every interaction; `evictAfterUse` for a rare specialist that would otherwise hold tens of gigabytes against a surface someone is actually using.

`residentBudgetGigabytes` and `residentGigabytes` are **advisory and never enforced**. They record what this machine holds before it swaps — measured at ~48 GB, against which two resident 30B models came to ~51 GB and drove 18 GB of swap. Nothing blocks a configuration that exceeds them.

Nothing reads this catalog yet. The first caller is the passive-tier composer (NIC-250).
