// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-vision",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "claude-vision",
            dependencies: [
                "ClaudeVisionShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "claude-vision-app",
            dependencies: ["ClaudeVisionShared"]
        ),
        .target(
            name: "ClaudeVisionShared"
        ),
        .testTarget(
            name: "ClaudeVisionTests",
            dependencies: ["ClaudeVisionShared"]
        ),
    ]
)
