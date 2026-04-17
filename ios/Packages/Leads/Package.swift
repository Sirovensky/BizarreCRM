// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Leads",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Leads", targets: ["Leads"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Leads",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        )
    ]
)
