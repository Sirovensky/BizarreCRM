// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pos",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Pos", targets: ["Pos"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Inventory"),
        .package(path: "../Customers"),
        .package(path: "../Hardware")
    ],
    targets: [
        .target(
            name: "Pos",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Inventory", "Customers", "Hardware"]
        ),
        .testTarget(
            name: "PosTests",
            dependencies: ["Pos", "Networking", "Inventory", "Customers", "Hardware"]
        )
    ]
)
