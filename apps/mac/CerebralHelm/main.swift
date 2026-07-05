import AppKit

// Programmatic AppKit entry point — no storyboard or nib. The native shell owns
// its lifecycle explicitly (ADR-001), so `NSApplicationMain` is intentionally not
// used; `main.swift` constructs the application, installs the delegate, and runs.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
