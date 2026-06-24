// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CerebralHelm",
    products: [
        .library(name: "CerebralCore", targets: ["CerebralCore"]),
        .library(name: "CerebralTools", targets: ["CerebralTools"]),
        .library(name: "CerebralKnowledge", targets: ["CerebralKnowledge"]),
        .library(name: "CerebralShared", targets: ["CerebralShared"]),
    ],
    targets: [
        .target(
            name: "CerebralShared",
            path: "packages/shared/Sources/CerebralShared"
        ),
        .target(
            name: "CerebralCore",
            dependencies: ["CerebralShared"],
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
            ],
            path: "Tests/RepositoryBoundaryTests"
        ),
    ]
)
