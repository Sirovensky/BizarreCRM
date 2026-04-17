// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Search",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Search", targets: ["Search"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Search",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        )
    ]
)
