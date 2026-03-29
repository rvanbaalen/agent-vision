// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agent-vision",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "agent-vision",
            dependencies: [
                "AgentVisionShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "AgentVisionShared"
        ),
        .testTarget(
            name: "AgentVisionTests",
            dependencies: ["AgentVisionShared"]
        ),
    ]
)
