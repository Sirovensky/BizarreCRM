// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Inventory",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Inventory", targets: ["Inventory"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Inventory",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "InventoryTests",
            dependencies: ["Inventory", "Networking", "Persistence"]
        )
    ]
)
