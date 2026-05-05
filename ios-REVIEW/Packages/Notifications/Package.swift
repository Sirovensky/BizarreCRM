// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notifications",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Notifications", targets: ["Notifications"])
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
            name: "Notifications",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "NotificationsTests",
            dependencies: ["Notifications", "Networking"]
        )
    ]
)
