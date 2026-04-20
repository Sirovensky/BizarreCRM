// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dashboard",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Dashboard", targets: ["Dashboard"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../Networking"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Dashboard",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence"]
        ),
        .testTarget(
            name: "DashboardTests",
            dependencies: ["Dashboard", "Networking"]
        )
    ]
)
