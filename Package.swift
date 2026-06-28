// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CerebralHelm",
    products: [
        .library(name: "CerebralCore", targets: ["CerebralCore"]),
        .library(name: "CerebralTools", targets: ["CerebralTools"]),
        .library(name: "CerebralKnowledge", targets: ["CerebralKnowledge"]),
        .library(name: "CerebralStorage", targets: ["CerebralStorage"]),
        .library(name: "CerebralShared", targets: ["CerebralShared"]),
        .library(name: "CerebralContracts", targets: ["CerebralContracts"]),
        .executable(name: "cerebral", targets: ["cerebral"]),
    ],
    dependencies: [
        // Pinned to the 1.1.x line on purpose: 1.2.0+ ships SwiftPM command
        // plugins (GenerateManual / GenerateDoccReference) whose shared sources
        // are referenced through directory symlinks. SwiftPM on Windows does not
        // traverse those symlinks when gathering plugin sources, so `swift test`
        // (which builds the whole package graph) fails to compile the plugins.
        // 1.1.x predates the plugins and is fully compatible with the CLI API we
        // use. Revisit when the toolchain stops building dependency plugins.
        .package(url: "https://github.com/apple/swift-argument-parser.git", "1.1.0" ..< "1.2.0"),
        // The SQLite amalgamation as a portable C target. This is the only SQLite
        // engine that builds on the Windows dev toolchain (GRDB and SQLite.swift do
        // not — see ADR-005). Pinned to the exact revision the engine probe
        // validated (tag 1.0.10 + 1). GRDB is the post-Mac target, tracked as tech
        // debt; it drops in behind the same CerebralStorage wrapper.
        .package(
            url: "https://github.com/swiftlang/swift-toolchain-sqlite.git",
            revision: "24de861aae133231803d89af8a88dc50b5b2e2dd"
        ),
    ],
    targets: [
        .target(
            name: "CerebralContracts",
            path: "packages/contracts/Sources/CerebralContracts"
        ),
        .target(
            name: "CerebralShared",
            path: "packages/shared/Sources/CerebralShared"
        ),
        .target(
            name: "CerebralCore",
            dependencies: ["CerebralShared", "CerebralContracts"],
            path: "packages/core/Sources/CerebralCore"
        ),
        .target(
            name: "CerebralTools",
            dependencies: ["CerebralCore", "CerebralShared", "CerebralContracts"],
            path: "packages/tools/Sources/CerebralTools"
        ),
        .target(
            name: "CerebralKnowledge",
            dependencies: ["CerebralCore", "CerebralShared"],
            path: "packages/knowledge/Sources/CerebralKnowledge"
        ),
        .target(
            name: "CerebralStorage",
            dependencies: [
                "CerebralCore",
                "CerebralShared",
                .product(name: "SwiftToolchainCSQLite", package: "swift-toolchain-sqlite"),
            ],
            path: "packages/storage/Sources/CerebralStorage"
        ),
        .executableTarget(
            name: "cerebral",
            dependencies: [
                "CerebralCore",
                "CerebralTools",
                "CerebralShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "apps/cli/Sources/cerebral"
        ),
        .testTarget(
            name: "RepositoryBoundaryTests",
            dependencies: [
                "CerebralCore",
                "CerebralTools",
                "CerebralKnowledge",
                "CerebralStorage",
                "CerebralShared",
                "CerebralContracts",
            ],
            path: "Tests/RepositoryBoundaryTests"
        ),
        .testTarget(
            name: "CoreModelTests",
            dependencies: [
                "CerebralCore",
                "CerebralShared",
                "CerebralContracts",
            ],
            path: "Tests/CoreModelTests"
        ),
        .testTarget(
            name: "SpineRegressionTests",
            dependencies: [
                "CerebralCore",
                "CerebralShared",
                "CerebralContracts",
            ],
            path: "Tests/SpineRegressionTests"
        ),
        .testTarget(
            name: "ToolsTests",
            dependencies: [
                "CerebralTools",
                "CerebralCore",
                "CerebralShared",
                "CerebralContracts",
            ],
            path: "Tests/ToolsTests"
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: [
                "CerebralCore",
                "CerebralContracts",
            ],
            path: "Tests/ConfigTests"
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: [
                "CerebralStorage",
                "CerebralCore",
                "CerebralShared",
            ],
            path: "Tests/StorageTests"
        ),
    ]
)
