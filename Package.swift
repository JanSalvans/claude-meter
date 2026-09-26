// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClaudeMeterCore",
            path: "Sources/ClaudeMeterCore"
        ),
        .executableTarget(
            name: "ClaudeMeter",
            dependencies: ["ClaudeMeterCore"],
            path: "Sources/ClaudeMeter"
        ),
        .testTarget(
            name: "ClaudeMeterTests",
            dependencies: ["ClaudeMeterCore"],
            path: "Tests/ClaudeMeterTests"
        )
    ]
)
