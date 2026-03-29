// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Build",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Build",
            path: "Build",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        )
    ]
)
