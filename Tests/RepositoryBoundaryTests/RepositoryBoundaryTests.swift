import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralShared
import CerebralStorage
import CerebralTools

@Test("portable modules expose their repository boundaries")
func portableModulesAreAvailable() {
    #expect(CerebralContractsPackage.boundary == "contracts")
    #expect(CerebralCorePackage.boundary == "core")
    #expect(CerebralToolsPackage.boundary == "tools")
    #expect(CerebralKnowledgePackage.boundary == "knowledge")
    #expect(CerebralStoragePackage.boundary == "storage")
    #expect(CerebralSharedPackage.boundary == "shared")
}

// Repository boundary rule 1 (docs/architecture/repository-boundaries.md) / PRD NFR-02:
// `packages/` must compile on non-Mac environments. That is broader than just AppKit:
// it forbids any native UI toolkit import (AppKit, Cocoa, UIKit) and native
// process/workspace control that only exists on Apple platforms.
//
// Pattern choices, kept narrow to avoid false positives:
//   * Imports are matched at line start, tolerating the `@_exported` / `@testable`
//     attributes that legitimately precede an import, for AppKit/Cocoa/UIKit.
//   * `NSWorkspace` is matched with word boundaries so it cannot fire on a longer
//     identifier that merely contains those characters.
//   * Foundation's `Process` is intentionally NOT matched as a bare `\bProcess\b`,
//     because portable code legitimately defines abstractions such as
//     `ProcessCapability` and `ProcessRunResult`. We only flag the two forms that
//     denote real native process execution: the fully-qualified `Foundation.Process`
//     and direct `Process(` construction.
private let forbiddenPortablePatterns: [(label: String, pattern: String)] = [
    ("import AppKit/Cocoa/UIKit", #"(?m)^\s*(?:@_exported\s+|@testable\s+)?import\s+(?:AppKit|Cocoa|UIKit)\b"#),
    ("NSWorkspace", #"\bNSWorkspace\b"#),
    ("native Process execution", #"(?:\bFoundation\.Process\b|\bProcess\s*\()"#),
]

/// Returns the labels of every forbidden pattern that matches `source`.
private func portableBoundaryViolations(in source: String) throws -> [String] {
    let range = NSRange(source.startIndex..., in: source)
    var matched: [String] = []
    for (label, pattern) in forbiddenPortablePatterns {
        let regex = try NSRegularExpression(pattern: pattern)
        if regex.firstMatch(in: source, range: range) != nil {
            matched.append(label)
        }
    }
    return matched
}

@Test("portability guard fires on each forbidden construct")
func portabilityGuardRejectsForbiddenConstructs() throws {
    // One violating literal per forbidden case. These are inline strings, NOT files
    // under packages/, so they exercise the matchers without breaking the build or
    // the real source scan below.
    #expect(try portableBoundaryViolations(in: "import AppKit").contains("import AppKit/Cocoa/UIKit"))
    #expect(try portableBoundaryViolations(in: "import Cocoa").contains("import AppKit/Cocoa/UIKit"))
    #expect(try portableBoundaryViolations(in: "import UIKit").contains("import AppKit/Cocoa/UIKit"))
    #expect(try portableBoundaryViolations(in: "@_exported import AppKit").contains("import AppKit/Cocoa/UIKit"))
    #expect(try portableBoundaryViolations(in: "let ws = NSWorkspace.shared").contains("NSWorkspace"))
    #expect(try portableBoundaryViolations(in: "let p = Foundation.Process()").contains("native Process execution"))
    #expect(try portableBoundaryViolations(in: "let p = Process()").contains("native Process execution"))

    // The narrowing must not flag legitimate portable identifiers.
    #expect(try portableBoundaryViolations(in: "protocol ProcessCapability {}").isEmpty)
    #expect(try portableBoundaryViolations(in: "struct ProcessRunResult {}").isEmpty)
    #expect(try portableBoundaryViolations(in: "import Foundation").isEmpty)
}

@Test("portable package sources stay platform-portable")
func portablePackagesStayPortable() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let packagesRoot = repositoryRoot.appendingPathComponent("packages", isDirectory: true)
    let files = FileManager.default.enumerator(
        at: packagesRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    )

    var violations: [String] = []
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: file, encoding: .utf8)
        let matched = try portableBoundaryViolations(in: source)
        if !matched.isEmpty {
            violations.append("\(file.path): \(matched.joined(separator: ", "))")
        }
    }

    #expect(violations.isEmpty)
}

// ADR-006 (Consequences): SQLite is the single source of truth for operational
// history, and `RepositoryBoundaryTests` must assert that `CerebralStorage` is the
// ONLY package linking the SQLite C target (`SwiftToolchainCSQLite`). This
// reinforces the ADR-005 boundary so the engine cannot leak into Core / Tools /
// Knowledge / Contracts / Shared.
//
// The check scans every `.swift` under `packages/` for `import SwiftToolchainCSQLite`
// and fails if any importer lives outside `packages/storage` (the `CerebralStorage`
// package).
@Test("only CerebralStorage links the SQLite C target")
func onlyStorageLinksSQLiteEngine() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let packagesRoot = repositoryRoot.appendingPathComponent("packages", isDirectory: true)
    let storageRoot = packagesRoot.appendingPathComponent("storage", isDirectory: true)

    // Matched at line start, tolerating the `@_exported` / `@testable` attributes
    // that legitimately precede an import, mirroring the AppKit/Cocoa/UIKit matcher.
    let importPattern = #"(?m)^\s*(?:@_exported\s+|@testable\s+)?import\s+SwiftToolchainCSQLite\b"#
    let regex = try NSRegularExpression(pattern: importPattern)

    let files = FileManager.default.enumerator(
        at: packagesRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    )

    var violations: [String] = []
    var storageImporters = 0
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(source.startIndex..., in: source)
        guard regex.firstMatch(in: source, range: range) != nil else { continue }

        // `storageRoot` is the only allowed location for the SQLite engine import.
        if file.path.hasPrefix(storageRoot.path) {
            storageImporters += 1
        } else {
            violations.append(file.path)
        }
    }

    #expect(violations.isEmpty)
    // Sanity check: the import must still exist somewhere under CerebralStorage, so
    // the test fails loudly if the engine is renamed/removed rather than passing
    // vacuously.
    #expect(storageImporters > 0)
}

// NIC-116: `CerebralKnowledge` is the ONLY package that may import Yams.
//
// The knowledge module parses user-authored note frontmatter, which is real YAML — tag lists,
// nested mappings, block scalars — so it needs a real parser. `CerebralShared` deliberately keeps
// its own narrow, dependency-free reader (``MarkdownFrontmatter``) instead of sharing this one,
// because *every* package depends on Shared: putting a C-backed parser there would pull libYAML
// into Core, Tools, Storage, and Contracts to serve one integer key in `PROJECT.md`.
//
// Same shape and same reasoning as the SQLite confinement above — a dependency that belongs to one
// package's job should not become everyone's transitive weight. If a second package ever genuinely
// needs YAML, that is a deliberate decision to make, not something to discover from a build graph.
@Test("only CerebralKnowledge imports the YAML parser")
func onlyKnowledgeImportsYams() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let packagesRoot = repositoryRoot.appendingPathComponent("packages", isDirectory: true)
    let knowledgeRoot = packagesRoot.appendingPathComponent("knowledge", isDirectory: true)

    let importPattern = #"(?m)^\s*(?:@_exported\s+|@testable\s+)?import\s+Yams\b"#
    let regex = try NSRegularExpression(pattern: importPattern)

    let files = FileManager.default.enumerator(
        at: packagesRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    )

    var violations: [String] = []
    var knowledgeImporters = 0
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(source.startIndex..., in: source)
        guard regex.firstMatch(in: source, range: range) != nil else { continue }

        if file.path.hasPrefix(knowledgeRoot.path) {
            knowledgeImporters += 1
        } else {
            violations.append(file.path)
        }
    }

    #expect(violations.isEmpty)
    // Fails loudly rather than vacuously if the parser is swapped out or the import renamed.
    #expect(knowledgeImporters > 0)
}
