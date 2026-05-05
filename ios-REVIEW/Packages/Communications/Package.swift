// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Communications",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Communications", targets: ["Communications"])
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
            name: "Communications",
            dependencies: ["Core", "DesignSystem", "Networking", "Persistence", "Sync"]
        ),
        .testTarget(
            name: "CommunicationsTests",
            dependencies: ["Communications", "Networking"],
            path: "Tests/CommunicationsTests"
        )
    ]
)
