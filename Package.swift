// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntigravityCodex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AntigravityCodex",
            targets: ["AntigravityCodex"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AntigravityCodex",
            path: "Sources"
        )
    ]
)
