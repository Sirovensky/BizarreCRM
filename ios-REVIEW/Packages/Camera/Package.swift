// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Camera",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Camera", targets: ["Camera"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Camera",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "CameraTests",
            dependencies: ["Camera", "Core"],
            path: "Tests/CameraTests"
        )
    ]
)
