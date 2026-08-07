import Foundation
import Testing

import CerebralCore

/// The in-memory registry that scopes URL tab surfacing to "opened by CH in the
/// current mode" (NIC-145). Records are keyed by `(modeID, urlID)`.
@Test("the registry recalls a recorded (mode, url) pair and keeps records scoped by mode and url")
func registryScopesByModeAndURL() {
    let registry = SessionURLOpenRegistry()

    #expect(!registry.contains(modeID: "executive", urlID: "github"))

    registry.record(modeID: "executive", urlID: "github")
    #expect(registry.contains(modeID: "executive", urlID: "github"))

    // The same url in a different mode is a distinct record — surfacing is
    // per-mode, so it must not leak across modes.
    #expect(!registry.contains(modeID: "developer", urlID: "github"))
    // The same mode with a different url is also distinct.
    #expect(!registry.contains(modeID: "executive", urlID: "docs"))
}

@Test("recording the same pair twice is idempotent")
func registryRecordingIsIdempotent() {
    let registry = SessionURLOpenRegistry()
    registry.record(modeID: "executive", urlID: "github")
    registry.record(modeID: "executive", urlID: "github")
    #expect(registry.contains(modeID: "executive", urlID: "github"))
}
