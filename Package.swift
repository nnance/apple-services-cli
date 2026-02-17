// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "apple-services",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "apple-services",
            path: "Sources/apple-services",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/apple-services/Info.plist"
                ])
            ]
        )
    ]
)
