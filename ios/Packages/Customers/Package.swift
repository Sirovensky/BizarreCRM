// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Customers",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Customers", targets: ["Customers"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence"),
        .package(path: "../Sync")
    ],
    targets: [
        .target(
            name: "Customers",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "CustomersTests",
            dependencies: ["Customers", "Networking", "Persistence"]
        )
    ]
)
