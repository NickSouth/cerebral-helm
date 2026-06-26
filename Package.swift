// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CerebralHelm",
    products: [
        .library(name: "CerebralCore", targets: ["CerebralCore"]),
        .library(name: "CerebralTools", targets: ["CerebralTools"]),
        .library(name: "CerebralKnowledge", targets: ["CerebralKnowledge"]),
        .library(name: "CerebralShared", targets: ["CerebralShared"]),
        .library(name: "CerebralContracts", targets: ["CerebralContracts"]),
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
            dependencies: ["CerebralCore", "CerebralShared"],
            path: "packages/tools/Sources/CerebralTools"
        ),
        .target(
            name: "CerebralKnowledge",
            dependencies: ["CerebralCore", "CerebralShared"],
            path: "packages/knowledge/Sources/CerebralKnowledge"
        ),
        .testTarget(
            name: "RepositoryBoundaryTests",
            dependencies: [
                "CerebralCore",
                "CerebralTools",
                "CerebralKnowledge",
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
    ]
)
