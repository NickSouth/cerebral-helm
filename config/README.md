# Configuration

**Owner:** Configuration

**Purpose:** Versioned, validated application defaults. User overrides and secrets never live in this repository.

Configuration cannot weaken hard safety invariants. Invalid configuration must leave the last-known-good configuration active.

NIC-12 increment 2 adds repository-owned JSON defaults for:

- application defaults;
- four modes;
- four configured agent surfaces;
- initial tool descriptors used by development validation.
