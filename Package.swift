// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TermGrid",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main")
    ],
    targets: [
        .target(
            name: "TermGridMLX",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/TermGridMLX"
        ),
        .executableTarget(
            name: "TermGrid",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "TermGridMLX",
            ],
            path: "Sources/TermGrid",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TermGridTests",
            dependencies: ["TermGrid"],
            path: "Tests/TermGridTests"
        )
    ]
)
