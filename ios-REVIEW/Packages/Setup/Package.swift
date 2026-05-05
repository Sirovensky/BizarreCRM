// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Setup",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Setup", targets: ["Setup"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking")
    ],
    targets: [
        .target(
            name: "Setup",
            dependencies: ["Core", "DesignSystem", "Networking"]
        ),
        .testTarget(
            name: "SetupTests",
            dependencies: ["Setup", "Core", "Networking"],
            path: "Tests/SetupTests"
        )
    ]
)
