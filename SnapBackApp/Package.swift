// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapBackApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SnapBackApp",
            path: "Sources/SnapBackApp"
        )
    ]
)
