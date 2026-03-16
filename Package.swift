// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TermGrid",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TermGrid",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
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
