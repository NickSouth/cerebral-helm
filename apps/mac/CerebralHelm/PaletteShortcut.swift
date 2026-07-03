import KeyboardShortcuts

/// The configurable global shortcut that summons the command palette (NIC-75 /
/// FR-SHL-02).
///
/// Default: **⌥Space** (Option-Space) — deliberately not ⌘Space (Spotlight) or ⌃Space
/// (the common input-source toggle). `KeyboardShortcuts` is Carbon-backed
/// (`RegisterEventHotKey`), so this fires system-wide without the Accessibility
/// permission (ADR-001 / TECH-STACK). The user can rebind or disable it from settings
/// (a follow-on increment); the name string is the durable persistence key, so it must
/// stay stable across releases.
extension KeyboardShortcuts.Name {
    // `KeyboardShortcuts.Name` is an immutable value but predates `Sendable`, so Swift 6
    // strict concurrency rejects it as a plain static. It is only ever read, so
    // `nonisolated(unsafe)` is the sanctioned annotation (per the package's Swift 6 guide).
    nonisolated(unsafe) static let summonPalette = Self("summonPalette", default: .init(.space, modifiers: [.option]))
}
