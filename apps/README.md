# Applications

**Owner:** Application surfaces

**Purpose:** Contain user-facing application entry points. Applications compose portable packages and adapters; they do not become shared domain libraries.

- `dashboard/` owns React presentation and emits user intent through the bridge contract.
- `mac/` will own the AppKit shell and native adapters.
- `ios/` reserves the future companion-app boundary and contains no MVP implementation.
