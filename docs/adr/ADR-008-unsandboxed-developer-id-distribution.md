# ADR-008: Unsandboxed Developer ID distribution for the MVP

- Status: Accepted
- Date: 2026-07-05

## Context

The native adapter epic (NIC-78) replaces the pre-Mac mock capabilities with
honest macOS implementations: NSWorkspace app/URL opening, allowlisted hook
process execution, live system metrics, Keychain secret resolution, and
permission status. Whether the app adopts the macOS App Sandbox changes how two
of those adapters can be built and where durable user state lands:

- **Hook execution (NIC-80, FR-TOL-05, FR-SAF-03).** A sandboxed app's child
  processes inherit its confinement, and no entitlement lets a child exceed the
  parent. Configured hooks exist to run the user's own scripts against their
  own files and repositories; under the sandbox those invocations fail with
  permission errors. Hook execution as specified is incompatible with a
  sandboxed process model.
- **Keychain secrets (NIC-82, FR-CFG-03).** Sandboxed and unsandboxed apps
  store keychain items under different identity semantics. Items written by
  one flavor are not cleanly readable after flipping the entitlement, which
  collides with the migration-safety principle: user state must never be
  silently reset or replaced.
- **Knowledge base.** A sandboxed app cannot read a user-chosen Markdown
  directory by plain path; it would need security-scoped bookmarks threaded
  through the knowledge layer.

The App Sandbox is mandatory only for Mac App Store distribution. Signed and
notarized Developer ID apps distributed outside the store do not require it.
The MVP PRD's packaging scope (signing, notarization, update channels,
migrations, backup, recovery) never requires App Store distribution.

The product's safety model is deliberately not OS containment: risk
classification, allowlists, and confirmation policy are deterministic and owned
by the policy layer (ADR-003). The product's value is broad, user-authorized
access to the user's machine.

## Decision

The MVP macOS app ships **unsandboxed**, signed with a Developer ID
certificate and notarized, distributed outside the Mac App Store.

Consequences for implementation:

- Native adapters (NIC-79..NIC-84) are designed against unsandboxed semantics:
  plain-path file access, unconfined `Process` execution for allowlisted
  hooks, and login-keychain items without app-group scoping.
- Keychain items created by the secret-store adapter are durable user state
  under the unsandboxed app identity.
- Safety continues to be enforced by the deterministic policy layer:
  descriptor-declared risk, exact-match hook allowlists, and confirmation
  policy. The sandbox is not part of the MVP threat model.

## Alternatives considered

- **Adopt the App Sandbox now.** Rejected: hook execution cannot meet its
  acceptance criteria, knowledge access needs bookmark plumbing the MVP has
  not budgeted, and the only distribution channel that requires it (Mac App
  Store) is not an MVP goal.
- **Sandbox with a privileged helper for hooks.** Rejected for MVP: adds an
  XPC service, a second signing identity, and an install step, for no current
  distribution requirement. May be revisited if App Store distribution ever
  becomes a goal.

## Consequences

- Mac App Store distribution is out of scope for the MVP build. Adopting the
  sandbox later is a real migration (container adoption, keychain item
  identity, security-scoped bookmarks, hook model redesign) and would need its
  own ADR and state-migration plan.
- The application's blast radius is bounded by policy, not by the OS; policy
  and allowlist tests remain the security boundary tests (FR-SAF-03,
  FR-SAF-07).
- Packaging work (signing, notarization, updates) targets Developer ID
  workflows.
