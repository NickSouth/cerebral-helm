import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralShared
import CerebralTools

@Test("portable modules expose their repository boundaries")
func portableModulesAreAvailable() {
    #expect(CerebralContractsPackage.boundary == "contracts")
    #expect(CerebralCorePackage.boundary == "core")
    #expect(CerebralToolsPackage.boundary == "tools")
    #expect(CerebralKnowledgePackage.boundary == "knowledge")
    #expect(CerebralSharedPackage.boundary == "shared")
}

@Test("portable package sources do not import AppKit")
func portablePackagesDoNotImportAppKit() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let packagesRoot = repositoryRoot.appendingPathComponent("packages", isDirectory: true)
    let appKitImport = try NSRegularExpression(
        pattern: #"(?m)^\s*(?:@_exported\s+|@testable\s+)?import\s+AppKit\b"#
    )
    let files = FileManager.default.enumerator(
        at: packagesRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    )

    var violations: [String] = []
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: file, encoding: .utf8)
        let range = NSRange(source.startIndex..., in: source)
        if appKitImport.firstMatch(in: source, range: range) != nil {
            violations.append(file.path)
        }
    }

    #expect(violations.isEmpty)
}
