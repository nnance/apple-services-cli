// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "apple-services",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "apple-services",
            path: "Sources/apple-services"
        )
    ]
)
