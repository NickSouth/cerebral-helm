# First-Mac Bootstrap Checklist

This runbook captures the first honest native validation pass for CerebralHelm on the initial target Mac. It exists to close the gap between portable Pre-Mac foundation work and real AppKit, `WKWebView`, hotkey, packaging, and platform-behavior validation.

## Target profile

### Expected first device

- Hardware: 16-inch MacBook Pro
- Chip generation target: Apple Silicon M5-class
- Memory target: 64 GB
- Storage target: 2 TB

### Operating system assumption

- Expected first validation OS: macOS `26.5.1`
- Current status: provisional, user-supplied planning assumption only

Do not convert the expected patch version into a hard compatibility invariant before the real machine is available. Record the exact shipped macOS version on the device during the first validation pass and update compatibility metadata from observed reality rather than planning assumptions.

## Preconditions

- The repository bootstrap and portable validation commands pass on the current development machine.
- The compatibility manifest remains the source of truth for contract and policy version comparisons.
- The target Mac is configured with a dedicated non-production CerebralHelm development root.
- No personal production knowledge root, production SQLite file, or production secret store is used for first native validation.

## First-pass capture

Record these values before validating behavior:

| Field | Value to capture | Status |
|---|---|---|
| Exact Mac model identifier | `unchecked` | `unchecked` |
| Exact chip name | `unchecked` | `unchecked` |
| Installed memory | `unchecked` | `unchecked` |
| Installed storage size | `unchecked` | `unchecked` |
| Exact macOS version | `unchecked` | `unchecked` |
| Xcode version | `unchecked` | `unchecked` |
| Swift version on device | `unchecked` | `unchecked` |

## Bootstrap validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| Clone and bootstrap repository | `corepack pnpm run bootstrap` and `swift test` | Portable dashboard build and Swift tests pass on the target Mac | `unchecked` |
| Confirm compatibility metadata | `corepack pnpm run validate-compatibility` | Manifest validation passes without local edits | `unchecked` |
| Confirm config and fixture validation | `corepack pnpm run validate-config` | Repository config and simulation fixtures validate | `unchecked` |
| Confirm dedicated development roots | inspect configured dev paths | All native validation roots point at dedicated development data, not personal production state | `unchecked` |

## Native shell validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| Manual application launch | launch native app target from local build | App launches offline without blank screen or immediate crash | `unchecked` |
| Startup validation behavior | start with current development root | App validates paths, schema versions, migrations, and bridge compatibility before accepting writes | `unchecked` |
| Recovery behavior | intentionally provoke one incompatible or missing prerequisite | App enters explicit read-only recovery guidance rather than mutating state silently | `unchecked` |
| Window roles | open dashboard, palette, settings, confirmation surfaces | Each role has deterministic ownership and no orphan duplicates | `unchecked` |
| Login item toggle | enable and disable login behavior | Launch-at-login setting can be changed without reinstalling | `unchecked` |

## Bridge and dashboard validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| Bundled dashboard load | launch native shell without dev server | Dashboard loads from local bundled assets only | `unchecked` |
| Bootstrap state handoff | inspect initial UI state | Dashboard receives capability-aware bootstrap state through the bridge | `unchecked` |
| Bridge handshake | inspect startup diagnostics | Bridge version, UI version, core version, capabilities, and degraded features are reported | `unchecked` |
| Major mismatch handling | run with forced incompatible bridge major version fixture if available | Recovery screen appears instead of silent continuation | `unchecked` |
| Mock/native parity spot check | compare key dashboard states against Pre-Mac fixture behavior | No transport-specific UI branching is required for equivalent state rendering | `unchecked` |

## Command and policy validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| Command palette opens | use global shortcut and in-app path | Exactly one palette instance opens and focuses correctly | `unchecked` |
| Direct command submission | submit a supported deterministic command | Command enters the shared lifecycle and emits observable state changes | `unchecked` |
| Confirmation flow | run a confirmation-gated action | Confirmation reflects policy-owned disclosure and decision handling | `unchecked` |
| Denied confirmation handling | deny a gated action | Command resolves as `cancelled`, not `failed` | `unchecked` |
| Event observability | inspect recent command and event output | Recent commands, confirmations, and structured errors are visible | `unchecked` |

## Native capability validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| App and URL open adapters | run allowlisted open actions | Configured applications and URLs open through native adapters | `unchecked` |
| Keychain-backed secret resolution | validate logical secret lookup path | Secrets resolve through Keychain references rather than plain config | `unchecked` |
| Status provider surface | inspect CPU, memory, network, battery, and display states as implemented | Supported metrics render honestly, unavailable metrics degrade clearly | `unchecked` |
| Global hotkey reliability | repeat open/close cycles across normal usage | Shortcut remains stable on the target macOS version | `unchecked` |

## Data safety validation

| Check | Command or action | Expected result | Status |
|---|---|---|---|
| Dedicated development root only | inspect filesystem outputs after app use | Native testing writes stay in dedicated development roots | `unchecked` |
| No personal production coupling | verify configured roots and logs | No command or bootstrap step defaults to personal production paths | `unchecked` |
| Recovery from disposable state | remove derived caches if implemented | Disposable indexes or caches can be rebuilt without durable-state loss | `unchecked` |
| Update preparation assumptions | inspect compatibility and update docs against real Mac | Native update prerequisites are clear before packaging work begins | `unchecked` |

## Evidence to attach after first run

- exact Mac model and macOS version;
- screenshots or logs for launch, dashboard load, bridge handshake, and recovery states;
- results for hotkey, confirmation, and event visibility checks;
- notes on anything that is unavailable, degraded, flaky, or version-sensitive;
- any compatibility manifest updates required from observed platform reality.

## Exit criteria

NIC-15 is satisfied when this checklist exists, the real platform validation items are explicitly marked `unchecked` before the Mac arrives, and the repository has an honest place to record observed results once the target Mac is available.
