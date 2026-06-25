# Contract Fixtures

Fixtures in this directory are shared across contract validation, Swift tests, dashboard mocks, simulations, and acceptance flows.

Future valid and invalid fixtures should use stable IDs, fixed clocks, and sanitized non-personal data.

Current fixture groups:

- `valid/bridge/`: valid bridge handshake, operation, event, and recovery examples shared by mock and future WKWebView transports.
- `valid/commands/`: valid command envelopes for MVP and reserved future sources.
- `valid/config/`: valid settings and config examples that are not already represented by checked-in `config/` defaults.
- `valid/lifecycle/`: valid lifecycle transition events.
- `valid/results/`: valid terminal command results.
- `valid/tools/`: valid MVP tool descriptors, confirmation disclosures, and tool results.
- `invalid/bridge/`: bridge examples that must fail validation.
- `invalid/commands/`: command envelope examples that must fail validation.
- `invalid/config/`: config examples that must fail validation.
- `invalid/lifecycle/`: lifecycle transition examples that must fail validation.
- `invalid/tools/`: tool descriptor examples that must fail validation.
