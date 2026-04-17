// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reports",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Reports", targets: ["Reports"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Reports",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        )
    ]
)
