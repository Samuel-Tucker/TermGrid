// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TermGrid",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TermGrid",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/TermGrid"
        ),
        .testTarget(
            name: "TermGridTests",
            dependencies: ["TermGrid"],
            path: "Tests/TermGridTests"
        )
    ]
)
