// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Estimates",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Estimates", targets: ["Estimates"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Customers"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Sync")
    ],
    targets: [
        .target(
            name: "Estimates",
            dependencies: ["Core", "Customers", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "EstimatesTests",
            dependencies: ["Estimates", "Networking", "Sync"]
        )
    ]
)
