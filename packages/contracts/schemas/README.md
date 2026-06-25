# Contract Schemas

JSON Schema 2020-12 documents in this directory are the canonical contract source.

NIC-16 through NIC-19 will add command, lifecycle event, tool, policy, confirmation, error, mode, agent, settings, config, and bridge schemas here.

Current schema groups:

- `bridge/`: bridge handshake, operation messages, bootstrap state, capability flags, degraded features, and events.
- `commands/`: command envelopes, lifecycle events, terminal command results, and shared structured errors.
- `config/`: application defaults, modes, agent surfaces, settings patches, and config validation errors.
- `tools/`: tool descriptors, policy-owned confirmation disclosures, and structured tool results.
